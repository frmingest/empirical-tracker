import Core
import Foundation

/// Trend signals, status assessment, and clinical targets for a single biomarker.
///
/// Ported from `web/src/lib/markerSignals.ts` and `web/src/lib/clinicalTargets.ts`
/// so the iOS detail view renders the same assessment the web app does. Pure,
/// value-type logic with no UI or networking — unit-testable in isolation.
public enum MarkerSignals {

    // MARK: - Thresholds

    /// A change of ≥50% versus the previous draw is a "large step".
    public static let largeStepFraction = 0.50
    /// A change of ≥25% versus the previous draw is "notable".
    public static let notableChangeFraction = 0.25
    /// Within 10% of the span of a bounded range counts as "near" that bound.
    public static let nearBoundFraction = 0.10

    // MARK: - Assessment

    /// Overall status for the badge, derived from the latest point plus trend signals.
    /// `watch` mirrors the web's "Watch" state: in-range now, but a large step or a
    /// trend toward a reference bound warrants a second look.
    public enum Assessment: Sendable {
        case inRange
        case outOfRange
        case watch
        case unknown
    }

    public static func assessment(for marker: BiomarkerWithSeries) -> Assessment {
        guard let latest = marker.latestResult else { return .unknown }
        switch latest.inRange {
        case .some(false):
            return .outOfRange
        case .none:
            return .unknown
        case .some(true):
            return signals(for: marker).contains { $0.severity == .watch } ? .watch : .inRange
        }
    }

    // MARK: - Signals

    public enum SignalKind: Sendable {
        case outOfRange
        case largeStep
        case notableChange
        case trendingTowardBound
    }

    public struct Signal: Identifiable, Sendable {
        public let id = UUID()
        public let kind: SignalKind
        public let title: String
        public let detail: String
        public let severity: Severity

        public enum Severity: Sendable {
            case alert   // out of range
            case watch   // large step / trending toward a bound
            case info    // notable but not alarming
        }
    }

    /// Computes the ordered list of signals for a marker (most severe first).
    public static func signals(for marker: BiomarkerWithSeries) -> [Signal] {
        let series = marker.series
        guard let latest = series.last else { return [] }
        var result: [Signal] = []

        if latest.inRange == false {
            result.append(Signal(
                kind: .outOfRange,
                title: "Out of range",
                detail: "The latest result falls outside the reference range.",
                severity: .alert
            ))
        }

        // Step change versus the previous draw.
        if series.count >= 2 {
            let previous = series[series.count - 2].value
            if previous != 0 {
                let pct = (latest.value - previous) / abs(previous)
                let direction = pct >= 0 ? "increase" : "decrease"
                let pctText = Self.percentText(abs(pct))
                if abs(pct) >= largeStepFraction {
                    result.append(Signal(
                        kind: .largeStep,
                        title: "Large change",
                        detail: "A \(pctText) \(direction) since the previous draw.",
                        severity: .watch
                    ))
                } else if abs(pct) >= notableChangeFraction {
                    result.append(Signal(
                        kind: .notableChange,
                        title: "Notable change",
                        detail: "A \(pctText) \(direction) since the previous draw.",
                        severity: .info
                    ))
                }
            }
        }

        // Trending toward a reference bound while still in range.
        if latest.inRange == true,
           let trend = boundTrend(for: marker) {
            result.append(trend)
        }

        return result.sorted { $0.severity.rank < $1.severity.rank }
    }

    /// Detects a marker that is in range but moving toward (and near) a reference bound.
    private static func boundTrend(for marker: BiomarkerWithSeries) -> Signal? {
        let series = marker.series
        guard series.count >= 2 else { return nil }
        let info = marker.biomarker
        let last = series[series.count - 1].value
        let prev = series[series.count - 2].value
        let delta = last - prev
        guard delta != 0 else { return nil }

        switch info.refType {
        case .bounded:
            guard let lo = info.refLow, let hi = info.refHigh, hi > lo else { return nil }
            let near = (hi - lo) * nearBoundFraction
            if delta > 0, hi - last <= near {
                return Signal(kind: .trendingTowardBound,
                              title: "Approaching upper limit",
                              detail: "Rising and near the top of the reference range.",
                              severity: .watch)
            }
            if delta < 0, last - lo <= near {
                return Signal(kind: .trendingTowardBound,
                              title: "Approaching lower limit",
                              detail: "Falling and near the bottom of the reference range.",
                              severity: .watch)
            }
        case .lt:
            guard let hi = info.refHigh, hi > 0 else { return nil }
            if delta > 0, hi - last <= hi * nearBoundFraction {
                return Signal(kind: .trendingTowardBound,
                              title: "Approaching upper limit",
                              detail: "Rising toward the reference cut-off.",
                              severity: .watch)
            }
        case .gt:
            guard let lo = info.refLow, lo > 0 else { return nil }
            if delta < 0, last - lo <= lo * nearBoundFraction {
                return Signal(kind: .trendingTowardBound,
                              title: "Approaching lower limit",
                              detail: "Falling toward the reference cut-off.",
                              severity: .watch)
            }
        case .none:
            return nil
        }
        return nil
    }

    // MARK: - Helpers

    private static func percentText(_ fraction: Double) -> String {
        "\(Int((fraction * 100).rounded()))%"
    }
}

private extension MarkerSignals.Signal.Severity {
    var rank: Int {
        switch self {
        case .alert: return 0
        case .watch: return 1
        case .info:  return 2
        }
    }
}

// MARK: - Clinical targets

/// An optimal-value reference line, distinct from the lab's reference range.
///
/// These are informational "optimal" targets (e.g. lipid goals) mirroring the
/// web's `clinicalTargets.ts`. They are decision-support only — never medical
/// advice — and are shown as a labelled dashed line on the trend chart.
public struct ClinicalTarget: Sendable {
    public let value: Double
    /// Short label for the chart annotation, e.g. "Optimal < 2.6".
    public let label: String

    public init(value: Double, label: String) {
        self.value = value
        self.label = label
    }
}

public extension BiomarkerInfo {
    /// Returns the optimal clinical target for this marker, if one is defined.
    /// Guarded by unit so a target is never drawn on a mismatched scale.
    var clinicalTarget: ClinicalTarget? {
        let name = (nameEn ?? nameNo).lowercased() + " " + nameNo.lowercased()
        let unitLower = (unit ?? "").lowercased()
        let isMmolPerL = unitLower.contains("mmol/l")

        // Lipids — optimal goals in mmol/L.
        if isMmolPerL {
            if name.contains("non-hdl") {
                return ClinicalTarget(value: 3.4, label: "Optimal < 3.4")
            }
            if name.contains("ldl") {
                return ClinicalTarget(value: 2.6, label: "Optimal < 2.6")
            }
            if name.contains("triglyserid") || name.contains("triglyceride") {
                return ClinicalTarget(value: 1.7, label: "Optimal < 1.7")
            }
            // Total cholesterol: "Kolesterol" without HDL/LDL qualifier.
            if name.contains("kolesterol"),
               !name.contains("hdl"), !name.contains("ldl") {
                return ClinicalTarget(value: 5.0, label: "Optimal < 5.0")
            }
        }

        // HbA1c — unit-dependent target.
        if name.contains("hba1c") {
            if unitLower.contains("mmol/mol") {
                return ClinicalTarget(value: 39, label: "Optimal < 39")
            }
            if unitLower.contains("%") {
                return ClinicalTarget(value: 5.7, label: "Optimal < 5.7")
            }
        }

        return nil
    }
}
