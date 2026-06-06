import Foundation
import WidgetKit

/// Read-only access to the snapshot written by the main app.
enum WidgetDataReader {

    static let appGroupID  = "group.app.empirical.tracker"
    static let snapshotKey = "widget_snapshot_v1"

    static func snapshot() -> WidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey),
            let snap = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return nil }
        return snap
    }

    /// Placeholder snapshot shown in widget gallery before real data is available.
    static func placeholder() -> WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: Date(),
            biomarkers: BiomarkerSummary(
                totalCount: 24,
                inRangeCount: 18,
                watchCount: 3,
                outOfRangeCount: 3,
                flaggedMarkers: [
                    FlaggedMarkerEntry(name: "LDL", value: 3.8, unit: "mmol/L",
                                       assessment: "outOfRange", trend: "rising"),
                    FlaggedMarkerEntry(name: "HbA1c", value: 48.0, unit: "mmol/mol",
                                       assessment: "watch", trend: "stable"),
                    FlaggedMarkerEntry(name: "Vitamin D", value: 42.0, unit: "nmol/L",
                                       assessment: "watch", trend: "falling"),
                ]
            ),
            weight: WeightSummary(
                latestKg: 82.4,
                latestDate: Date(),
                series: stride(from: -29, through: 0, by: 1).map { offset in
                    WeightPoint(
                        date: Calendar.current.date(byAdding: .day, value: offset, to: Date())!,
                        kg: 82.4 + Double.random(in: -0.5...0.5)
                    )
                }
            ),
            macros: MacroSummary(
                date: Date(),
                kcal: 1840,
                proteinG: 148,
                carbsG: 38,
                fatG: 112
            )
        )
    }
}
