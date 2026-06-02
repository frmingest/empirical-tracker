import BodyMetrics
import Core
import Foundation
import HealthSync
import Observation

/// UI-facing state and coordinator for the **Withings Cloud** connection (Sprint 10,
/// ADR-023) — Path B of the two-path Withings strategy.
///
/// Where `HealthSyncState` (Path A) reads Apple Health on-device, this drives the
/// server-to-server connection: it fetches the consent URL, presents it via
/// `ASWebAuthenticationSession`, then asks the backend to confirm status and pull
/// history. The backend (not the device) holds the Withings tokens and runs the
/// `Notify` webhooks; the app only kicks the flow off and reflects status.
///
/// A single instance is owned by `AppEnvironment` so the Body tab card and the Settings
/// detail share one connection state (matching the Apple Health pattern).
///
/// ### Self-gating on backend capability
/// The Withings Cloud endpoints are new backend work (migration plan §4.4) that may not
/// be deployed yet. Rather than show a button that 404s, the state starts `.unavailable`
/// and only reveals the feature once `GET /withings/connection` answers (a `404` keeps it
/// hidden). So the UI lights up automatically the moment the backend ships — no client
/// release required — and stays invisible until then.
@MainActor
@Observable
final class WithingsCloudState {

    enum Connection: Equatable {
        /// Backend hasn't shipped the Withings Cloud endpoints — hide the feature.
        case unavailable
        /// Available, but this user hasn't connected their Withings account.
        case notConnected
        /// The OAuth consent web session is in flight.
        case connecting
        /// Connected; the backend is pulling/receiving measurements.
        case connected
    }

    // MARK: - Observed state

    private(set) var connection: Connection = .unavailable
    private(set) var isSyncing = false
    private(set) var lastSyncDate: Date?
    private(set) var lastResult: WithingsSyncResult?
    var errorMessage: String?

    // MARK: - Dependencies

    private let service: WithingsCloudService
    private let bodyMetrics: BodyMetricsRepository
    private let authenticator: any WithingsWebAuthenticating
    /// True once `status()` has succeeded at least once, so a later transient network
    /// error doesn't make us hide a feature we know exists.
    private var hasConfirmedAvailability = false

    init(
        service: WithingsCloudService,
        bodyMetrics: BodyMetricsRepository,
        authenticator: any WithingsWebAuthenticating
    ) {
        self.service = service
        self.bodyMetrics = bodyMetrics
        self.authenticator = authenticator
    }

    convenience init(service: WithingsCloudService, bodyMetrics: BodyMetricsRepository) {
        self.init(service: service, bodyMetrics: bodyMetrics, authenticator: WithingsWebAuthenticator())
    }

    // MARK: - Lifecycle

    /// Called when the Body tab / Settings appear: resolve availability + status, then
    /// silently top up if connected.
    func refreshOnAppear() async {
        await refreshStatus()
        if connection == .connected {
            await syncNow(silent: true)
        }
    }

    /// Resolves the current connection state from the backend. A `404` means the Cloud
    /// endpoints aren't deployed → `.unavailable` (feature hidden). Other errors before
    /// we've ever confirmed availability also keep it hidden, so we never show a dead
    /// control on a backend that can't serve it.
    func refreshStatus() async {
        do {
            apply(try await service.status())
        } catch APIError.notFound {
            connection = .unavailable
        } catch {
            if !hasConfirmedAvailability { connection = .unavailable }
        }
    }

    private func apply(_ status: WithingsConnectionStatus) {
        hasConfirmedAvailability = true
        connection = status.connected ? .connected : .notConnected
        lastSyncDate = status.lastSyncAt
    }

    // MARK: - Connect / disconnect

    func connect() async {
        guard connection == .notConnected else { return }
        errorMessage = nil
        connection = .connecting
        do {
            let auth = try await service.authorize()
            let callback = try await authenticator.authenticate(
                url: auth.authorizeUrl,
                callbackScheme: WithingsCloudService.callbackScheme
            )
            guard WithingsCloudService.isSuccessCallback(callback) else {
                throw WithingsAuthError.cannotStart
            }
            // The backend completed the code→token exchange on the redirect; confirm
            // the new status and pull history.
            await refreshStatus()
            if connection == .connected {
                await syncNow()
            } else {
                connection = .notConnected
            }
        } catch WithingsAuthError.cancelled {
            connection = .notConnected
        } catch {
            errorMessage = error.localizedDescription
            await refreshStatus()
            if connection == .connecting { connection = .notConnected }
        }
    }

    /// Revokes the connection server-side and refreshes the (now empty) status. Rows
    /// already imported into the account are kept; the user can delete them by hand.
    func disconnect() async {
        errorMessage = nil
        do {
            try await service.disconnect()
        } catch {
            errorMessage = error.localizedDescription
        }
        connection = .notConnected
        lastSyncDate = nil
        lastResult = nil
        await bodyMetrics.load()
    }

    // MARK: - Sync

    func syncNow(silent: Bool = false) async {
        guard connection == .connected, !isSyncing else { return }
        isSyncing = true
        if !silent { errorMessage = nil }
        do {
            lastResult = try await service.sync()
            apply(try await service.status())
            // The repository is the source of truth; reload so the charts reflect any
            // newly imported Withings rows.
            await bodyMetrics.load()
        } catch {
            if !silent { errorMessage = error.localizedDescription }
        }
        isSyncing = false
    }
}
