import BodyMetrics
import Foundation
import HealthSync
import Observation

/// UI-facing state and coordinator for the Apple Health sync (Sprint 9, ADR-022).
///
/// The actor `HealthSyncManager` does the off-main HealthKit work; this `@Observable`
/// holds the screen-facing values (connection, last sync, per-type toggles, errors)
/// and drives the connect → authorize → sync → observe flow. After every sync it
/// reloads `BodyMetricsRepository` so the charts reconcile against the server, the
/// source of truth.
///
/// A single instance is owned by `AppEnvironment` so the Body tab and the Settings
/// detail share one connection state.
@MainActor
@Observable
final class HealthSyncState {

    enum Connection: Equatable {
        /// HealthKit isn't available on this device — hide the feature entirely.
        case unavailable
        /// Available but the user hasn't connected.
        case notConnected
        /// The user has granted (or chosen on) the permission sheet.
        case connected
    }

    // MARK: - Observed state

    private(set) var connection: Connection
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastSummary: HealthSyncManager.SyncSummary?
    var errorMessage: String?

    private var enabledTypes: Set<HealthMetricType>

    // MARK: - Dependencies

    private let manager: HealthSyncManager
    private let bodyMetrics: BodyMetricsRepository
    private let defaults: UserDefaults
    private var isObserving = false

    private enum Key {
        static let connected = "healthsync.connected"
        static let lastSync = "healthsync.lastSync"
        static let enabledTypes = "healthsync.enabledTypes"
    }

    // MARK: - Init

    init(
        manager: HealthSyncManager,
        bodyMetrics: BodyMetricsRepository,
        defaults: UserDefaults = .standard
    ) {
        self.manager = manager
        self.bodyMetrics = bodyMetrics
        self.defaults = defaults

        if let stored = defaults.stringArray(forKey: Key.enabledTypes) {
            enabledTypes = Set(stored.compactMap(HealthMetricType.init(rawValue:)))
        } else {
            enabledTypes = HealthMetricType.defaultEnabled
        }

        let available = HealthSyncManager.isHealthDataAvailable
        let wasConnected = defaults.bool(forKey: Key.connected)
        connection = available ? (wasConnected ? .connected : .notConnected) : .unavailable

        let stamp = defaults.double(forKey: Key.lastSync)
        lastSyncDate = stamp > 0 ? Date(timeIntervalSince1970: stamp) : nil
    }

    // MARK: - Type toggles (Settings)

    func isEnabled(_ type: HealthMetricType) -> Bool { enabledTypes.contains(type) }

    func setEnabled(_ type: HealthMetricType, _ isOn: Bool) {
        if isOn { enabledTypes.insert(type) } else { enabledTypes.remove(type) }
        defaults.set(enabledTypes.map(\.rawValue), forKey: Key.enabledTypes)
        guard connection == .connected else { return }
        // Widen authorization to any newly enabled type and re-arm observation.
        Task {
            try? await manager.requestAuthorization(for: enabledTypes)
            isObserving = false
            await ensureObserving()
            await syncNow(silent: true)
        }
    }

    // MARK: - Lifecycle

    /// Called when the Body tab appears: silently top-up and ensure observation.
    func refreshOnAppear() async {
        guard connection == .connected else { return }
        await ensureObserving()
        await syncNow(silent: true)
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard connection != .unavailable else { return }
        errorMessage = nil
        do {
            try await manager.requestAuthorization(for: enabledTypes)
            connection = .connected
            defaults.set(true, forKey: Key.connected)
            await syncNow()
            await ensureObserving()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Forgets the connection locally and stops background delivery. We deliberately
    /// keep the synced-UUID record so reconnecting doesn't re-upload rows that are
    /// already on the backend (there is no server-side `external_id` dedupe yet —
    /// migration plan §4.2). The user revokes the actual grant in Apple Health.
    func disconnect() {
        connection = .notConnected
        defaults.set(false, forKey: Key.connected)
        isObserving = false
        Task { await manager.stopObserving() }
    }

    // MARK: - Sync

    func syncNow(silent: Bool = false) async {
        guard connection == .connected, !isSyncing else { return }
        isSyncing = true
        if !silent { errorMessage = nil }
        do {
            let summary = try await manager.sync(types: enabledTypes)
            lastSummary = summary
            let now = Date()
            lastSyncDate = now
            defaults.set(now.timeIntervalSince1970, forKey: Key.lastSync)
            // The repository is the source of truth; reload so charts reflect dedupe.
            await bodyMetrics.load()
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
        isSyncing = false
    }

    // MARK: - Observation

    private func ensureObserving() async {
        guard connection == .connected, !isObserving, !enabledTypes.isEmpty else { return }
        do {
            try await manager.startObserving(types: enabledTypes) { [weak self] in
                await self?.syncNow(silent: true)
            }
            isObserving = true
        } catch {
            // Background delivery is best-effort; "Sync now" remains the fallback.
        }
    }
}
