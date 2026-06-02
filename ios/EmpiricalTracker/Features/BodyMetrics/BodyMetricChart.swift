import Charts
import Core
import DietEvents
import SwiftUI

/// Small generic trend chart for body metrics (ADR-017 §3).
///
/// Deliberately *not* an extension of `BiomarkerChart`: that chart is built around
/// lab reference ranges and a single value series, neither of which fits weight /
/// waist / blood pressure. This one takes one or two `Series` (blood pressure is the
/// two-line case), reuses `DietEventOverlayContent` for the correlation overlay, and
/// draws optional **guideline** lines as neutral, dashed, always-labelled references
/// — pointedly not styled like the Sprint 7 clinical-target line, because these are
/// general population references, not personalised targets.
struct BodyMetricChart: View {

    struct DataPoint: Identifiable {
        let id = UUID()
        let date: Date
        let value: Double
    }

    struct Series: Identifiable {
        let id: String
        let label: String
        let color: Color
        let points: [DataPoint]
    }

    /// A neutral population reference (e.g. blood pressure 120 / 80).
    struct Guideline: Identifiable {
        let id = UUID()
        let value: Double
    }

    let title: String
    let unit: String
    let series: [Series]
    var guidelines: [Guideline] = []
    let events: [DietEvent]

    /// A legend is only useful when more than one series is plotted (blood pressure).
    private var showsLegend: Bool { series.count > 1 }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(title)
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textPrimary)
                Text(unit)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            }

            chart
                .frame(height: 200)

            if showsLegend { legend }
        }
    }

    private var chart: some View {
        Chart {
            ForEach(series) { s in
                ForEach(s.points) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value),
                        series: .value("Metric", s.label)
                    )
                    .foregroundStyle(s.color)
                    .interpolationMethod(.monotone)

                    PointMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value)
                    )
                    .foregroundStyle(s.color)
                    .symbolSize(50)
                }
            }

            ForEach(guidelines) { guide in
                RuleMark(y: .value("Guideline", guide.value))
                    .foregroundStyle(Color.textMuted.opacity(0.5))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                    .annotation(position: .trailing, alignment: .leading, spacing: 2) {
                        Text(String(localized: "body.guideline"))
                            .font(.labelSmall)
                            .foregroundStyle(Color.textMuted)
                    }
            }

            DietEventOverlayContent(events: events)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: .dateTime.month(.abbreviated).year(.twoDigits))
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .accessibilityLabel(accessibilityLabel)
    }

    private var legend: some View {
        HStack(spacing: 16) {
            ForEach(series) { s in
                HStack(spacing: 5) {
                    Capsule()
                        .fill(s.color)
                        .frame(width: 16, height: 3)
                    Text(s.label)
                }
            }
        }
        .font(.labelMedium)
        .foregroundStyle(Color.textMuted)
    }

    private var accessibilityLabel: String {
        let count = series.reduce(0) { $0 + $1.points.count }
        return "\(title) trend chart in \(unit) with \(count) measurements."
    }
}
