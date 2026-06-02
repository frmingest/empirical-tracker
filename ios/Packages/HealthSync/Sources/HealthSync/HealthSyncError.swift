import Foundation

/// Errors surfaced by `HealthSyncManager`.
public enum HealthSyncError: Error, LocalizedError, Sendable {
    /// HealthKit is not available on this device (e.g. iPad without Health, or a
    /// platform where the framework can't be imported).
    case unavailable
    /// The user has not yet authorised — or actively denied — the requested types.
    case notAuthorized
    /// A wrapped HealthKit/query failure.
    case query(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable:
            return "Apple Health is not available on this device."
        case .notAuthorized:
            return "Apple Health access has not been granted."
        case .query(let message):
            return message
        }
    }
}
