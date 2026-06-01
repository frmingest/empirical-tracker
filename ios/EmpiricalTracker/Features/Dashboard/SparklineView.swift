import Charts
import Core
import SwiftUI

/// Mini trend sparkline shown on each BiomarkerCard.
/// Uses Swift Charts with a reference-range band shaded behind the line.
struct SparklineView: View {
    let series: [ResultPoint]
    let refLow: Double?
    let refHigh: Double?
    let refType: BiomarkerInfo.RefType

    private var domainPadding: Double {
        let values = series.map(\.value)
        guard let lo = values.min(), let hi = values.max(), hi > lo else { return 1 }
        return (hi - lo) * 0.3
    }

    var body: some View {
        Chart {
            referenceRuleMark
            referenceAreaMark
            lineMark
            pointMarks
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .chartLegend(.hidden)
        .frame(height: 44)
        .accessibilityHidden(true)
    }

    // MARK: - Chart content

    @ChartContentBuilder
    private var lineMark: some ChartContent {
        ForEach(series) { point in
            LineMark(
                x: .value("Date", point.testedAt),
                y: .value("Value", point.value)
            )
            .foregroundStyle(lineColor)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
            .interpolationMethod(.monotone)
        }
    }

    @ChartContentBuilder
    private var pointMarks: some ChartContent {
        if let last = series.last {
            PointMark(
                x: .value("Date", last.testedAt),
                y: .value("Value", last.value)
            )
            .foregroundStyle(lineColor)
            .symbolSize(20)
        }
    }

    @ChartContentBuilder
    private var referenceAreaMark: some ChartContent {
        if refType == .bounded, let lo = refLow, let hi = refHigh {
            RectangleMark(yStart: .value("Low", lo), yEnd: .value("High", hi))
                .foregroundStyle(Color.inRange.opacity(0.08))
        } else if refType == .lt, let hi = refHigh {
            RectangleMark(yEnd: .value("High", hi))
                .foregroundStyle(Color.inRange.opacity(0.08))
        } else if refType == .gt, let lo = refLow {
            RectangleMark(yStart: .value("Low", lo))
                .foregroundStyle(Color.inRange.opacity(0.08))
        }
    }

    @ChartContentBuilder
    private var referenceRuleMark: some ChartContent {
        if refType == .lt, let hi = refHigh {
            RuleMark(y: .value("Ref", hi))
                .foregroundStyle(Color.inRange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        } else if refType == .gt, let lo = refLow {
            RuleMark(y: .value("Ref", lo))
                .foregroundStyle(Color.inRange.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
        }
    }

    // MARK: - Color

    private var lineColor: Color {
        guard let latest = series.last else { return .textMuted }
        switch latest.inRange {
        case .some(true):  return .inRange
        case .some(false): return .outRange
        case .none:        return .accent
        }
    }
}

// MARK: - Preview

#Preview {
    let series = MockData.biomarkerSeries.first!
    return SparklineView(
        series: series.series,
        refLow: series.biomarker.refLow,
        refHigh: series.biomarker.refHigh,
        refType: series.biomarker.refType
    )
    .padding()
    .background(Color.bgCard)
}
