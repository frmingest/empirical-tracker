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
    public let heartRateBpm: Int?
    public let restingHeartRateBpm: Int?
    public let hrvMs: Double?
    public let note: String?
    /// `manual` | `healthkit` | `withings`.
    public let source: Source

    public enum Source: String, Codable, Sendable {
        case manual
        case healthkit
        case withings
    }

    public init(
        id: String,
        measuredOn: Date,
        weightKg: Double? = nil,
        waistCm: Double? = nil,
        systolic: Int? = nil,
        diastolic: Int? = nil,
        heartRateBpm: Int? = nil,
        restingHeartRateBpm: Int? = nil,
        hrvMs: Double? = nil,
        note: String? = nil,
        source: Source = .manual
    ) {
        self.id = id
        self.measuredOn = measuredOn
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.systolic = systolic
        self.diastolic = diastolic
        self.heartRateBpm = heartRateBpm
        self.restingHeartRateBpm = restingHeartRateBpm
        self.hrvMs = hrvMs
        self.note = note
        self.source = source
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id                   = try c.decode(String.self, forKey: .id)
        measuredOn           = try c.decode(Date.self, forKey: .measuredOn)
        weightKg             = try c.decodeIfPresent(Double.self, forKey: .weightKg)
        waistCm              = try c.decodeIfPresent(Double.self, forKey: .waistCm)
        systolic             = try c.decodeIfPresent(Int.self, forKey: .systolic)
        diastolic            = try c.decodeIfPresent(Int.self, forKey: .diastolic)
        heartRateBpm         = try c.decodeIfPresent(Int.self, forKey: .heartRateBpm)
        restingHeartRateBpm  = try c.decodeIfPresent(Int.self, forKey: .restingHeartRateBpm)
        hrvMs                = try c.decodeIfPresent(Double.self, forKey: .hrvMs)
        note                 = try c.decodeIfPresent(String.self, forKey: .note)
        source               = try c.decodeIfPresent(Source.self, forKey: .source) ?? .manual
    }
}

// MARK: - Payload

public struct BodyMetricPayload: Encodable, Sendable {
    public let measuredOn: Date
    public let weightKg: Double?
    public let waistCm: Double?
    public let systolic: Int?
    public let diastolic: Int?
    public let heartRateBpm: Int?
    public let restingHeartRateBpm: Int?
    public let hrvMs: Double?
    public let note: String?
    /// Provenance of the reading. `nil` lets the backend default to `manual`.
    public let source: BodyMetric.Source?

    public init(
        measuredOn: Date = .now,
        weightKg: Double? = nil,
        waistCm: Double? = nil,
        systolic: Int? = nil,
        diastolic: Int? = nil,
        heartRateBpm: Int? = nil,
        restingHeartRateBpm: Int? = nil,
        hrvMs: Double? = nil,
        note: String? = nil,
        source: BodyMetric.Source? = nil
    ) {
        self.measuredOn = measuredOn
        self.weightKg = weightKg
        self.waistCm = waistCm
        self.systolic = systolic
        self.diastolic = diastolic
        self.heartRateBpm = heartRateBpm
        self.restingHeartRateBpm = restingHeartRateBpm
        self.hrvMs = hrvMs
        self.note = note
        self.source = source
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

    /// Inserts multiple readings in a single POST. Used by the HealthKit sync path
    /// to replace thousands of per-sample requests with batches of up to 200.
    public func createBatch(_ payloads: [BodyMetricPayload]) async throws {
        let created: [BodyMetric] = try await client.request(.post("/body-metrics/batch", body: payloads))
        metrics.append(contentsOf: created)
        metrics.sort { $0.measuredOn < $1.measuredOn }
    }

    public func delete(id: String) async throws {
        try await client.requestEmpty(.delete("/body-metrics/\(id)"))
        metrics.removeAll { $0.id == id }
    }

    public func deleteBySource(_ source: BodyMetric.Source) async throws {
        try await client.requestEmpty(.delete("/body-metrics/by-source/\(source.rawValue)"))
        metrics.removeAll { $0.source == source }
    }
}
