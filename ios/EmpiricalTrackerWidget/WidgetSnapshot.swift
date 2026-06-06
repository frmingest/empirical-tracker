import Foundation

// MARK: - WidgetSnapshot
// NOTE: This file is a verbatim copy of EmpiricalTracker/Features/Widgets/WidgetSnapshot.swift.
// Both must be kept in sync. It is duplicated (rather than shared via SPM) because
// widget extensions cannot import app targets directly.

public struct WidgetSnapshot: Codable, Sendable {
    public let updatedAt: Date
    public let biomarkers: BiomarkerSummary
    public let weight: WeightSummary?
    public let macros: MacroSummary?
}

public struct BiomarkerSummary: Codable, Sendable {
    public let totalCount: Int
    public let inRangeCount: Int
    public let watchCount: Int
    public let outOfRangeCount: Int
    public let flaggedMarkers: [FlaggedMarkerEntry]

    public var outOfRangeOrWatchCount: Int { watchCount + outOfRangeCount }
}

public struct FlaggedMarkerEntry: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let value: Double
    public let unit: String
    public let assessment: String
    public let trend: String

    public var isOutOfRange: Bool { assessment == "outOfRange" }

    public var trendSymbol: String {
        switch trend {
        case "rising":  return "↑"
        case "falling": return "↓"
        default:        return "→"
        }
    }
}

public struct WeightSummary: Codable, Sendable {
    public let latestKg: Double
    public let latestDate: Date
    public let series: [WeightPoint]

    public var trend: String {
        guard series.count >= 2 else { return "stable" }
        let delta = series.last!.kg - series[series.count - 2].kg
        if delta >  0.3 { return "rising" }
        if delta < -0.3 { return "falling" }
        return "stable"
    }
}

public struct WeightPoint: Codable, Sendable {
    public let date: Date
    public let kg: Double
}

public struct MacroSummary: Codable, Sendable {
    public let date: Date
    public let kcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double
}
