import Foundation

// MARK: - BiomarkerInfo

/// Mirrors `BiomarkerInfo` in `web/src/lib/api.ts`.
public struct BiomarkerInfo: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    /// Norwegian lab name (primary key in the DB: `name_no`).
    public let nameNo: String
    /// English translation, if available.
    public let nameEn: String?
    public let unit: String?
    /// Raw reference range string as printed on the lab report, e.g. "4,5 - 5,8".
    public let refRangeRaw: String
    public let refLow: Double?
    public let refHigh: Double?
    public let refType: RefType

    public enum RefType: String, Codable, Sendable {
        case bounded
        case lt        // upper-bound only ("< N")
        case gt        // lower-bound only ("> N")
        case none
    }

    public init(
        id: String,
        nameNo: String,
        nameEn: String? = nil,
        unit: String? = nil,
        refRangeRaw: String,
        refLow: Double? = nil,
        refHigh: Double? = nil,
        refType: RefType
    ) {
        self.id = id
        self.nameNo = nameNo
        self.nameEn = nameEn
        self.unit = unit
        self.refRangeRaw = refRangeRaw
        self.refLow = refLow
        self.refHigh = refHigh
        self.refType = refType
    }

    /// Human-readable display name: English if set, Norwegian otherwise.
    public var displayName: String { nameEn ?? nameNo }
}

// MARK: - ResultPoint

/// A single time-series measurement for a biomarker.
public struct ResultPoint: Codable, Identifiable, Hashable, Sendable {
    public var id: String { "\(testedAt.timeIntervalSince1970)" }
    public let testedAt: Date
    public let value: Double
    /// nil means the reference range is absent (`ref_type == "none"`).
    public let inRange: Bool?

    public init(testedAt: Date, value: Double, inRange: Bool?) {
        self.testedAt = testedAt
        self.value = value
        self.inRange = inRange
    }
}

// MARK: - BiomarkerWithSeries

/// Full biomarker plus its complete time-series. Response of `GET /biomarkers/results`.
public struct BiomarkerWithSeries: Codable, Identifiable, Hashable, Sendable {
    public var id: String { biomarker.id }
    public let biomarker: BiomarkerInfo
    /// Sorted chronologically by the backend.
    public let series: [ResultPoint]

    public init(biomarker: BiomarkerInfo, series: [ResultPoint]) {
        self.biomarker = biomarker
        self.series = series
    }

    public var latestResult: ResultPoint? { series.last }

    public var trend: Trend {
        guard series.count >= 2 else { return .stable }
        let last  = series[series.count - 1].value
        let prev  = series[series.count - 2].value
        guard prev != 0 else { return .stable }
        let pct = (last - prev) / abs(prev)
        if pct >  0.05 { return .rising }
        if pct < -0.05 { return .falling }
        return .stable
    }

    public enum Trend: Sendable { case rising, falling, stable }
}

// MARK: - Panel

/// Represents a single blood-draw session. Response of `GET /biomarkers/panels`.
public struct Panel: Codable, Identifiable, Sendable {
    public let id: String
    public let testedAt: Date
    public let source: String
    public let resultCount: Int?
    public let inRangeCount: Int?
    public let outRangeCount: Int?

    public init(
        id: String,
        testedAt: Date,
        source: String,
        resultCount: Int? = nil,
        inRangeCount: Int? = nil,
        outRangeCount: Int? = nil
    ) {
        self.id = id
        self.testedAt = testedAt
        self.source = source
        self.resultCount = resultCount
        self.inRangeCount = inRangeCount
        self.outRangeCount = outRangeCount
    }
}

// MARK: - ManualResultPayload (POST body)

/// Body of `POST /biomarkers/results/manual`.
///
/// The backend identifies the biomarker by its **`biomarker_id`** (the
/// `biomarkers.id` primary key), not by `name_no`, and computes `in_range`
/// itself from the stored reference range. See ADR-007.
public struct ManualResultPayload: Encodable, Sendable {
    /// `biomarkers.id` — the biomarker this result belongs to.
    public let biomarkerId: String
    public let value: Double
    public let testedAt: Date

    public init(biomarkerId: String, value: Double, testedAt: Date) {
        self.biomarkerId = biomarkerId
        self.value = value
        self.testedAt = testedAt
    }

    enum CodingKeys: String, CodingKey {
        case biomarkerId, value, testedAt
    }

    /// `tested_at` is encoded as a calendar date (`yyyy-MM-dd`) rather than a
    /// full ISO-8601 timestamp. Sending a UTC timestamp for a midnight-local
    /// `Date` shifts the day backwards for positive-offset time zones (e.g.
    /// `2026-06-02` local midnight serialises as `2026-06-01T22:00:00Z` in CEST),
    /// which would file the result under the wrong day. See `CalendarDate`.
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(biomarkerId, forKey: .biomarkerId)
        try container.encode(value, forKey: .value)
        try container.encode(CalendarDate.string(from: testedAt), forKey: .testedAt)
    }
}
