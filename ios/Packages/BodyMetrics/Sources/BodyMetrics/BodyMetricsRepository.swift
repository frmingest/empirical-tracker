import Core
import Foundation
import Observation

// MARK: - BodyMetric model

/// A single body-metrics measurement. Provenance field prepared for Sprint 8/9/10.
public struct BodyMetric: Codable, Identifiable, Sendable {
    public let id: String
    public let measuredOn: Date
    public let weightKg: Double?
    public let waistCm: Double?
    public let systolic: Int?
    public let diastolic: Int?
    /// `manual` | `healthkit` | `withings` — added in Sprint 8 backend migration.
    public let source: Source

    public enum Source: String, Codable, Sendable {
        case manual
        case healthkit
        case withings
    }
}

// MARK: - Payload

public struct BodyMetricPayload: Encodable, Sendable {
    public let measuredOn: Date
    public let weightKg: Double?
    public let waistCm: Double?
    public let systolic: Int?
    public let diastolic: Int?

    public init(
        measuredOn: Date = .now,
        weightKg: Double? = nil,
        waistCm: Double? = nil,
        systolic: Int? = nil,
        diastolic: Int? = nil
    ) {
        self.measuredOn = measuredOn
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.systolic = systolic
        self.diastolic = diastolic
    }
}

// MARK: - Repository (stub — wired fully in Sprint 8)

@MainActor
@Observable
public final class BodyMetricsRepository {
    public var metrics: [BodyMetric] = []
    public var isLoading = false
    public var error: APIError?

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    public func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            metrics = try await client.request(.get("/body-metrics"))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
    }

    public func create(_ payload: BodyMetricPayload) async throws {
        let metric: BodyMetric = try await client.request(.post("/body-metrics", body: payload))
        metrics.append(metric)
        metrics.sort { $0.measuredOn < $1.measuredOn }
    }

    public func delete(id: String) async throws {
        try await client.requestEmpty(.delete("/body-metrics/\(id)"))
        metrics.removeAll { $0.id == id }
    }
}
