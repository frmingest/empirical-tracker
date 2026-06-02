import BodyMetrics
import HealthSync

/// Bridges `HealthSyncManager`'s uploads onto the real backend: each mapped Apple
/// Health reading is POSTed through `BodyMetricsRepository` (so it lands in
/// `body_metrics` and the in-memory list, exactly like a manual entry — only tagged
/// `source: healthkit`). Kept in the app layer so the `HealthSync` package stays
/// backend-agnostic and unit-testable with an in-memory sink.
@MainActor
final class RepositoryBodyMetricSyncSink: BodyMetricSyncSink {
    private let repository: BodyMetricsRepository

    init(repository: BodyMetricsRepository) {
        self.repository = repository
    }

    func upload(_ payload: BodyMetricPayload) async throws {
        try await repository.create(payload)
    }
}
