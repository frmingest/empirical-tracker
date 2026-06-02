import Foundation

/// Remembers which HealthKit sample UUIDs have already been pushed to the backend,
/// so re-syncs (and background deliveries) never insert the same reading twice.
///
/// This is the **client-side** half of the dedupe story: it prevents *this device*
/// re-uploading a sample it already sent. The server-side complement — an
/// `external_id` column on `body_metrics` that also rejects the same reading
/// arriving via the Withings Cloud path (migration plan §4.2 / §4.3) — is backend
/// work tracked for Sprint 10. Until then, one device + one cloud path could still
/// double-count; with HealthKit-only (Sprint 9) the local set is sufficient.
public actor SyncedSampleStore {
    private let defaults: UserDefaults
    private let key = "healthsync.syncedSampleIDs"
    private var ids: Set<String>

    /// - Parameter suiteName: a `UserDefaults` suite, used by tests for isolation.
    ///   Falls back to `.standard` when `nil` or unresolvable.
    public init(suiteName: String? = nil) {
        let store = suiteName.flatMap { UserDefaults(suiteName: $0) } ?? .standard
        self.defaults = store
        self.ids = Set(store.stringArray(forKey: key) ?? [])
    }

    public func contains(_ uuid: String) -> Bool {
        ids.contains(uuid)
    }

    public func insert(_ uuid: String) {
        guard ids.insert(uuid).inserted else { return }
        persist()
    }

    public var count: Int { ids.count }

    /// Clears the record. Called on disconnect so a fresh connect re-imports history.
    public func reset() {
        ids.removeAll()
        defaults.removeObject(forKey: key)
    }

    private func persist() {
        defaults.set(Array(ids), forKey: key)
    }
}
