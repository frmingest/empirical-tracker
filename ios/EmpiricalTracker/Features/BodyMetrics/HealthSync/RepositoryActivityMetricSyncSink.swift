import BodyMetrics
import HealthSync

/// Bridges `HealthSyncManager.syncActivity` onto the real backend.
/// Delegates to `ActivityMetricsRepository` for the UPSERT call so the package
/// stays backend-agnostic.
@MainActor
final class RepositoryActivityMetricSyncSink: ActivityMetricSyncSink {
    private let repository: ActivityMetricsRepository

    init(repository: ActivityMetricsRepository) {
        self.repository = repository
    }

    func uploadBatch(_ payloads: [ActivityMetricPayload]) async throws {
        try await repository.upsertBatch(payloads)
    }
}
