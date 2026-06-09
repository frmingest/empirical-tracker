import Foundation

/// Where `HealthSyncManager.syncActivity` sends the daily activity rows it maps
/// out of Apple Health. Parallel to `BodyMetricSyncSink` but for activity data.
public protocol ActivityMetricSyncSink: Sendable {
    /// Upsert a batch of daily activity payloads in a single round-trip.
    /// Throwing aborts the whole batch (the day-keys are not recorded; the
    /// next sync retries without re-pulling an unlimited history window).
    func uploadBatch(_ payloads: [ActivityMetricPayload]) async throws
}
