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
///
/// **Depth** — a gradient area fills the space under the line and each point is
/// drawn as a ringed marker (a colored dot cut out of a card-colored halo) so
/// the trend reads as a raised surface rather than a flat stroke.
///
/// **Interactivity** — when `isInteractive` is set, tapping or dragging across
/// the chart snaps to the nearest measurement and floats a callout showing that
/// reading's exact value and date. The category grid leaves this off because
/// the whole card is a navigation button and must not swallow the tap.
struct BiomarkerTrendChart: View {
    let marker: BiomarkerWithSeries
    /// Diet events intersecting the marker window, drawn as a correlation overlay.
    var dietEvents: [DietEvent] = []
    /// Enables tap/drag selection of individual measurements.
    var isInteractive: Bool = false

    /// Raw x-position from the selection gesture; snapped to a real point below.
    @State private var selectedDate: Date?

    private var info: BiomarkerInfo { marker.biomarker }

    /// The measurement nearest the user's touch, snapped to a real data point.
    private var selectedPoint: ResultPoint? {
        guard isInteractive, let selectedDate else { return nil }
        return marker.series.min {
            abs($0.testedAt.timeIntervalSince(selectedDate)) <
            abs($1.testedAt.timeIntervalSince(selectedDate))
        }
    }

    var body: some View {
        if isInteractive {
            chart
                .chartXSelection(value: $selectedDate)
                .sensoryFeedback(.selection, trigger: selectedPoint?.id)
        } else {
            chart
        }
    }

    private var chart: some View {
        Chart {
            referenceBand
            referenceRules
            clinicalTargetRule
            DietEventOverlayContent(events: dietEvents)
            areaFill
            seriesLine
            seriesPoints
            selectionMarks
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

    /// Gradient area under the line — the main "depth" cue, giving the trend
    /// volume instead of a hairline stroke.
    @ChartContentBuilder
    private var areaFill: some ChartContent {
        ForEach(marker.series) { point in
            AreaMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accent.opacity(0.26), Color.accent.opacity(0.015)],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private var seriesLine: some ChartContent {
        ForEach(marker.series) { point in
            LineMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(
                LinearGradient(
                    colors: [Color.accent, Color.accent.opacity(0.65)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
            .interpolationMethod(.monotone)
        }
    }

    /// Each measurement is drawn as a colored dot sitting on a card-colored
    /// halo. The halo "cuts" the dot out of the line and the area beneath it,
    /// giving the points separation and a raised feel without per-mark shadows
    /// (which Swift Charts marks don't support).
    @ChartContentBuilder
    private var seriesPoints: some ChartContent {
        ForEach(marker.series) { point in
            PointMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color.bgCard)
            .symbolSize(130)
            .symbol(.circle)

            PointMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(pointColor(point))
            .symbolSize(55)
            .symbol(.circle)
        }
    }

    /// Lollipop rule + halo'd point + floating callout for the active selection.
    @ChartContentBuilder
    private var selectionMarks: some ChartContent {
        if let point = selectedPoint {
            RuleMark(x: .value("Selected", point.testedAt))
                .foregroundStyle(Color.textMuted.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(
                    position: .top,
                    spacing: 8,
                    overflowResolution: .init(x: .fit(to: .chart), y: .disabled)
                ) {
                    calloutCard(point)
                }

            // Glow ring → card-colored cut → colored core, stacked largest-first.
            PointMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(pointColor(point).opacity(0.22))
            .symbolSize(420)
            .symbol(.circle)

            PointMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(Color.bgCard)
            .symbolSize(170)
            .symbol(.circle)

            PointMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(pointColor(point))
            .symbolSize(90)
            .symbol(.circle)
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

    // MARK: - Selection callout

    /// Floating card naming the exact value + date of the selected measurement.
    private func calloutCard(_ point: ResultPoint) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(point.testedAt.formatted(.dateTime.day().month(.abbreviated).year()))
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Circle()
                    .fill(pointColor(point))
                    .frame(width: 7, height: 7)
                Text(formattedValue(point.value))
                    .font(.numericSmall)
                    .foregroundStyle(Color.textPrimary)
                if let unit = info.unit {
                    Text(unit)
                        .font(.labelMedium)
                        .foregroundStyle(Color.textMuted)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.bgElevated, in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(Color.borderCard, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.18), radius: 6, x: 0, y: 3)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Helpers

    private func pointColor(_ point: ResultPoint) -> Color {
        switch point.inRange {
        case .some(true):  return .inRange
        case .some(false): return .outRange
        case .none:        return .accent
        }
    }

    private func formattedValue(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }
}
