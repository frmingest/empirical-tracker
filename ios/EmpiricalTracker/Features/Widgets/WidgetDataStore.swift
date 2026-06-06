import Biomarkers
import BodyMetrics
import Core
import Foundation
import FoodDiary

/// Writes a `WidgetSnapshot` to the App Group shared container so the widget
/// extension can read fresh data without a network round-trip.
///
/// Call `write(from:bodyMetrics:foodEntries:)` after every successful data
/// load in `AppEnvironment`. The widget extension uses `WidgetDataStore.read()`
/// to load the last-saved snapshot.
///
/// App Group ID: `group.com.FaizMalik.EmpiricalTracker`
/// This must be added to both the app and widget targets in Xcode:
///   Signing & Capabilities → + Capability → App Groups → group.com.FaizMalik.EmpiricalTracker
final class WidgetDataStore {

    static let appGroupID = "group.com.FaizMalik.EmpiricalTracker"
    static let snapshotKey = "widget_snapshot_v1"

    // MARK: - Write (called from app)

    @MainActor
    func write(
        biomarkerResults: [BiomarkerWithSeries],
        bodyMetrics: [BodyMetric],
        foodEntries: [FoodEntry]
    ) {
        let snapshot = buildSnapshot(
            biomarkerResults: biomarkerResults,
            bodyMetrics: bodyMetrics,
            foodEntries: foodEntries
        )
        guard
            let defaults = UserDefaults(suiteName: Self.appGroupID),
            let data = try? JSONEncoder().encode(snapshot)
        else { return }
        defaults.set(data, forKey: Self.snapshotKey)
        // Ask WidgetKit to reload all timelines so the widget shows fresh data.
        // Import WidgetKit only in the app target; use the string-based API here
        // via a notification so WidgetKit is not a hard dependency of this file.
        NotificationCenter.default.post(name: .widgetSnapshotDidUpdate, object: nil)
    }

    // MARK: - Read (called from widget extension)

    static func read() -> WidgetSnapshot? {
        guard
            let defaults = UserDefaults(suiteName: appGroupID),
            let data = defaults.data(forKey: snapshotKey),
            let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return nil }
        return snapshot
    }

    // MARK: - Builder

    @MainActor
    private func buildSnapshot(
        biomarkerResults: [BiomarkerWithSeries],
        bodyMetrics: [BodyMetric],
        foodEntries: [FoodEntry]
    ) -> WidgetSnapshot {
        WidgetSnapshot(
            updatedAt: Date(),
            biomarkers: buildBiomarkerSummary(biomarkerResults),
            weight: buildWeightSummary(bodyMetrics),
            macros: buildMacroSummary(foodEntries)
        )
    }

    private func buildBiomarkerSummary(_ results: [BiomarkerWithSeries]) -> BiomarkerSummary {
        var inRange = 0, watch = 0, outOfRange = 0
        var flagged: [FlaggedMarkerEntry] = []

        for item in results {
            let assessment = MarkerSignals.assessment(for: item)
            switch assessment {
            case .inRange:    inRange += 1
            case .watch:      watch += 1
            case .outOfRange: outOfRange += 1
            case .unknown:    break
            }
            guard assessment == .watch || assessment == .outOfRange,
                  let latest = item.latestResult else { continue }
            flagged.append(FlaggedMarkerEntry(
                name: item.biomarker.displayName,
                value: latest.value,
                unit: item.biomarker.unit ?? "",
                assessment: assessment == .outOfRange ? "outOfRange" : "watch",
                trend: item.trend == .rising ? "rising" : item.trend == .falling ? "falling" : "stable"
            ))
        }

        // Sort: out-of-range first, then watch; alphabetically within each group.
        flagged.sort {
            if $0.isOutOfRange != $1.isOutOfRange { return $0.isOutOfRange }
            return $0.name < $1.name
        }

        return BiomarkerSummary(
            totalCount: results.count,
            inRangeCount: inRange,
            watchCount: watch,
            outOfRangeCount: outOfRange,
            flaggedMarkers: Array(flagged.prefix(4))
        )
    }

    private func buildWeightSummary(_ metrics: [BodyMetric]) -> WeightSummary? {
        let withWeight = metrics
            .filter { $0.weightKg != nil }
            .sorted { $0.measuredOn < $1.measuredOn }
        guard let latest = withWeight.last else { return nil }

        let thirtyDaysAgo = Calendar.current.date(byAdding: .day, value: -30, to: Date()) ?? Date()
        let series = withWeight
            .filter { $0.measuredOn >= thirtyDaysAgo }
            .map { WeightPoint(date: $0.measuredOn, kg: $0.weightKg!) }

        return WeightSummary(
            latestKg: latest.weightKg!,
            latestDate: latest.measuredOn,
            series: series
        )
    }

    private func buildMacroSummary(_ entries: [FoodEntry]) -> MacroSummary? {
        guard !entries.isEmpty else { return nil }
        let kcal    = entries.compactMap(\.energyKcal).reduce(0, +)
        let protein = entries.compactMap(\.proteinG).reduce(0, +)
        let carbs   = entries.compactMap(\.carbsG).reduce(0, +)
        let fat     = entries.compactMap(\.fatG).reduce(0, +)
        guard kcal > 0 || protein > 0 || carbs > 0 || fat > 0 else { return nil }
        return MacroSummary(
            date: Calendar.current.startOfDay(for: Date()),
            kcal: kcal,
            proteinG: protein,
            carbsG: carbs,
            fatG: fat
        )
    }
}

// MARK: - Notification name

extension Notification.Name {
    static let widgetSnapshotDidUpdate = Notification.Name("app.empirical.tracker.widgetSnapshotDidUpdate")
}
