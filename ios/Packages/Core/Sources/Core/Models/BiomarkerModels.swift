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

    /// Human-readable display name: English if set, Norwegian otherwise.
    public var displayName: String { nameEn ?? nameNo }
}

// MARK: - ResultPoint

/// A single time-series measurement for a biomarker.
public struct ResultPoint: Codable, Identifiable, Sendable {
    public var id: String { "\(testedAt.timeIntervalSince1970)" }
    public let testedAt: Date
    public let value: Double
    /// nil means the reference range is absent (`ref_type == "none"`).
    public let inRange: Bool?
}

// MARK: - BiomarkerWithSeries

/// Full biomarker plus its complete time-series. Response of `GET /biomarkers/results`.
public struct BiomarkerWithSeries: Codable, Identifiable, Sendable {
    public var id: String { biomarker.id }
    public let biomarker: BiomarkerInfo
    /// Sorted chronologically by the backend.
    public let series: [ResultPoint]

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
}

// MARK: - ManualResultPayload (POST body)

public struct ManualResultPayload: Encodable, Sendable {
    public let nameNo: String
    public let nameEn: String?
    public let unit: String?
    public let value: Double
    public let testedAt: Date
    public let refRangeRaw: String?

    public init(
        nameNo: String,
        nameEn: String? = nil,
        unit: String? = nil,
        value: Double,
        testedAt: Date,
        refRangeRaw: String? = nil
    ) {
        self.nameNo = nameNo
        self.nameEn = nameEn
        self.unit = unit
        self.value = value
        self.testedAt = testedAt
        self.refRangeRaw = refRangeRaw
    }
}
