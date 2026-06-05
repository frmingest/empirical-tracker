import Foundation

// MARK: - WidgetSnapshot

/// Lightweight snapshot written to the App Group shared container by the main
/// app after each data load, and read by the widget extension (which has no
/// network access). Both targets must include this file.
public struct WidgetSnapshot: Codable, Sendable {
    public let updatedAt: Date
    public let biomarkers: BiomarkerSummary
    public let weight: WeightSummary?
    public let macros: MacroSummary?

    public init(
        updatedAt: Date,
        biomarkers: BiomarkerSummary,
        weight: WeightSummary?,
        macros: MacroSummary?
    ) {
        self.updatedAt = updatedAt
        self.biomarkers = biomarkers
        self.weight = weight
        self.macros = macros
    }
}

// MARK: - BiomarkerSummary

public struct BiomarkerSummary: Codable, Sendable {
    public let totalCount: Int
    public let inRangeCount: Int
    public let watchCount: Int
    public let outOfRangeCount: Int
    /// Up to 4 flagged markers for the medium widget, sorted worst-first.
    public let flaggedMarkers: [FlaggedMarkerEntry]

    public var outOfRangeOrWatchCount: Int { watchCount + outOfRangeCount }

    public init(
        totalCount: Int,
        inRangeCount: Int,
        watchCount: Int,
        outOfRangeCount: Int,
        flaggedMarkers: [FlaggedMarkerEntry]
    ) {
        self.totalCount = totalCount
        self.inRangeCount = inRangeCount
        self.watchCount = watchCount
        self.outOfRangeCount = outOfRangeCount
        self.flaggedMarkers = flaggedMarkers
    }
}

public struct FlaggedMarkerEntry: Codable, Sendable, Identifiable {
    public var id: String { name }
    public let name: String
    public let value: Double
    public let unit: String
    /// "outOfRange" | "watch"
    public let assessment: String
    /// "rising" | "falling" | "stable"
    public let trend: String

    public var isOutOfRange: Bool { assessment == "outOfRange" }

    public init(name: String, value: Double, unit: String, assessment: String, trend: String) {
        self.name = name
        self.value = value
        self.unit = unit
        self.assessment = assessment
        self.trend = trend
    }

    public var trendSymbol: String {
        switch trend {
        case "rising":  return "↑"
        case "falling": return "↓"
        default:        return "→"
        }
    }
}

// MARK: - WeightSummary

public struct WeightSummary: Codable, Sendable {
    public let latestKg: Double
    public let latestDate: Date
    /// Last 30 days, chronological. Used by the weight-trend widget sparkline.
    public let series: [WeightPoint]

    public init(latestKg: Double, latestDate: Date, series: [WeightPoint]) {
        self.latestKg = latestKg
        self.latestDate = latestDate
        self.series = series
    }

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

    public init(date: Date, kg: Double) {
        self.date = date
        self.kg = kg
    }
}

// MARK: - MacroSummary

public struct MacroSummary: Codable, Sendable {
    public let date: Date
    public let kcal: Double
    public let proteinG: Double
    public let carbsG: Double
    public let fatG: Double

    public init(date: Date, kcal: Double, proteinG: Double, carbsG: Double, fatG: Double) {
        self.date = date
        self.kcal = kcal
        self.proteinG = proteinG
        self.carbsG = carbsG
        self.fatG = fatG
    }
}
