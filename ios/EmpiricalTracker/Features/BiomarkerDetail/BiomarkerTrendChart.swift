import Biomarkers
import Charts
import Core
import DietEvents
import SwiftUI

/// The full biomarker trend chart: reference band/rules, clinical target,
/// diet-event overlay, and the measured line + points.
///
/// Extracted from `BiomarkerDetailView` so the per-category graph view
/// (`CategoryGraphsView`) renders an identical chart without duplicating the
/// Swift Charts content. The caller controls the height via `.frame(height:)`.
struct BiomarkerTrendChart: View {
    let marker: BiomarkerWithSeries
    /// Diet events intersecting the marker window, drawn as a correlation overlay.
    var dietEvents: [DietEvent] = []

    private var info: BiomarkerInfo { marker.biomarker }

    var body: some View {
        Chart {
            referenceBand
            referenceRules
            clinicalTargetRule
            DietEventOverlayContent(events: dietEvents)
            seriesLine
            seriesPoints
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading)
        }
        .accessibilityLabel("\(info.displayName) trend chart with \(marker.series.count) measurements.")
    }

    // MARK: - Chart content

    @ChartContentBuilder
    private var seriesLine: some ChartContent {
        ForEach(marker.series) { point in
            LineMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color.accent)
            .lineStyle(StrokeStyle(lineWidth: 2))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private var seriesPoints: some ChartContent {
        ForEach(marker.series) { point in
            PointMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(pointColor(point))
            .symbolSize(60)
        }
    }

    @ChartContentBuilder
    private var referenceBand: some ChartContent {
        if info.refType == .bounded, let lo = info.refLow, let hi = info.refHigh {
            RectangleMark(yStart: .value("Low", lo), yEnd: .value("High", hi))
                .foregroundStyle(Color.inRange.opacity(0.08))
        }
    }

    @ChartContentBuilder
    private var referenceRules: some ChartContent {
        if info.refType == .bounded {
            if let lo = info.refLow {
                RuleMark(y: .value("Lower ref", lo))
                    .foregroundStyle(Color.inRange.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
            if let hi = info.refHigh {
                RuleMark(y: .value("Upper ref", hi))
                    .foregroundStyle(Color.inRange.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
            }
        } else if info.refType == .lt, let hi = info.refHigh {
            RuleMark(y: .value("Upper ref", hi))
                .foregroundStyle(Color.inRange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        } else if info.refType == .gt, let lo = info.refLow {
            RuleMark(y: .value("Lower ref", lo))
                .foregroundStyle(Color.inRange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    @ChartContentBuilder
    private var clinicalTargetRule: some ChartContent {
        if let target = info.clinicalTarget {
            RuleMark(y: .value("Target", target.value))
                .foregroundStyle(Color.accent.opacity(0.7))
                .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 3]))
                .annotation(position: .top, alignment: .trailing, spacing: 2) {
                    Text(target.label)
                        .font(.labelSmall)
                        .foregroundStyle(Color.accent)
                }
        }
    }

    private func pointColor(_ point: ResultPoint) -> Color {
        switch point.inRange {
        case .some(true):  return .inRange
        case .some(false): return .outRange
        case .none:        return .accent
        }
    }
}
