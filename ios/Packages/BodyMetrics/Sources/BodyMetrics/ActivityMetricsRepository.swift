import Core
import Foundation
import Observation

// MARK: - ActivityMetric model

public struct ActivityMetric: Codable, Identifiable, Sendable {
    public let id: String
    public let measuredOn: Date
    public let steps: Int?
    public let activeEnergyKcal: Double?
    public let exerciseMinutes: Int?
    public let source: String

    public init(
        id: String,
        measuredOn: Date,
        steps: Int? = nil,
        activeEnergyKcal: Double? = nil,
        exerciseMinutes: Int? = nil,
        source: String = "healthkit"
    ) {
        self.id = id
        self.measuredOn = measuredOn
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.source = source
    }
}

// MARK: - Repository

@MainActor
@Observable
public final class ActivityMetricsRepository {
    public var metrics: [ActivityMetric] = []
    public var isLoading = false
    public var error: APIError?

    /// When true, the repository serves only its seeded in-memory data and skips
    /// network fetches — used by the sample-data explore mode and previews.
    public var isLocalOnly = false

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func load() async {
        guard !isLocalOnly else { return }
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            metrics = try await client.request(.get("/activity-metrics"))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
    }

    /// Upserts a batch of daily activity payloads (one round-trip).
    /// Uses requestEmpty to avoid decoding the upsert response — the backend
    /// may return numeric columns as JSON strings (Postgres `numeric` type),
    /// which would fail ActivityMetric decoding. `load()` fetches the real data.
    public func upsertBatch(_ payloads: [some Encodable & Sendable]) async throws {
        guard !payloads.isEmpty else { return }
        try await client.requestEmpty(.post("/activity-metrics/batch", body: payloads))
        await load()
    }

    public func deleteBySource(_ source: String) async throws {
        try await client.requestEmpty(.delete("/activity-metrics/by-source/\(source)"))
        metrics.removeAll { $0.source == source }
    }
}
