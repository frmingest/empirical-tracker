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
///
/// For long timeseries (e.g. 5+ years of Apple Health data) the chart exposes a
/// range selector (3M / 6M / 1Y / All) and overlays a 7-day moving average so the
/// trend stays readable even with daily, noisy measurements.
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

    enum ChartRange: String, CaseIterable {
        case threeMonths = "3M"
        case sixMonths   = "6M"
        case oneYear     = "1Y"
        case all         = "All"

        func startDate(relativeTo end: Date) -> Date? {
            let cal = Calendar.current
            switch self {
            case .threeMonths: return cal.date(byAdding: .month,  value: -3,  to: end)
            case .sixMonths:   return cal.date(byAdding: .month,  value: -6,  to: end)
            case .oneYear:     return cal.date(byAdding: .year,   value: -1,  to: end)
            case .all:         return nil
            }
        }
    }

    let title: String
    let unit: String
    let series: [Series]
    var guidelines: [Guideline] = []
    let events: [DietEvent]

    @State private var selectedRange: ChartRange = .all

    // MARK: - Derived

    private var allPoints: [DataPoint] {
        series.flatMap(\.points).sorted { $0.date < $1.date }
    }

    /// Earliest date across all series, used to decide whether range buttons are useful.
    private var dataStart: Date? { allPoints.first?.date }
    private var dataEnd:   Date? { allPoints.last?.date }

    /// True when the data spans more than 6 months — only then do we show the picker.
    private var showsRangePicker: Bool {
        guard let s = dataStart, let e = dataEnd else { return false }
        return e.timeIntervalSince(s) > 6 * 30 * 24 * 3600
    }

    /// The cutoff date for the currently selected range.
    private var rangeStart: Date? {
        guard let end = dataEnd else { return nil }
        return selectedRange.startDate(relativeTo: end)
    }

    /// Filter a series to the visible range.
    private func visiblePoints(for s: Series) -> [DataPoint] {
        guard let cutoff = rangeStart else { return s.points }
        return s.points.filter { $0.date >= cutoff }
    }

    /// 7-day rolling average — O(n) sliding window instead of O(n²) filter-per-point.
    private func movingAverage(for s: Series) -> [DataPoint] {
        let pts = visiblePoints(for: s)
        guard pts.count > 7 else { return [] }
        let windowDuration: TimeInterval = 7 * 24 * 3600
        var lo = 0
        var windowSum = 0.0
        var result = [DataPoint]()
        result.reserveCapacity(pts.count)
        for (i, point) in pts.enumerated() {
            windowSum += point.value
            while pts[lo].date < point.date.addingTimeInterval(-windowDuration) {
                windowSum -= pts[lo].value
                lo += 1
            }
            result.append(DataPoint(date: point.date, value: windowSum / Double(i - lo + 1)))
        }
        return result
    }

    /// Reduce a sorted array to at most `maxCount` evenly-spaced points,
    /// always preserving the first and last. Charts can't display more than a
    /// few hundred distinct pixels horizontally anyway.
    private static func downsample(_ points: [DataPoint], to maxCount: Int) -> [DataPoint] {
        guard points.count > maxCount else { return points }
        let stride = Double(points.count - 1) / Double(maxCount - 1)
        return (0..<maxCount).map { i in points[Int((Double(i) * stride).rounded())] }
    }

    /// Show raw dots only when the range is short enough that they don't clutter.
    private var showsPoints: Bool { selectedRange == .threeMonths || selectedRange == .sixMonths }

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
                Spacer()
                if showsRangePicker { rangePicker }
            }

            chart
                .frame(height: 200)

            if showsLegend { legend }
        }
    }

    // MARK: - Range picker

    private var rangePicker: some View {
        HStack(spacing: 4) {
            ForEach(ChartRange.allCases, id: \.self) { range in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { selectedRange = range }
                } label: {
                    Text(range.rawValue)
                        .font(.labelSmall)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(
                            selectedRange == range ? Color.accent : Color.bgElevated,
                            in: Capsule()
                        )
                        .foregroundStyle(selectedRange == range ? Color.white : Color.textMuted)
                }
                .buttonStyle(.plain)
            }
        }
    }

    // MARK: - Chart

    private var chart: some View {
        Chart {
            // Raw data — faded when moving average is present.
            // Downsampled to ≤400 points: Charts can't render more distinct
            // pixels than that horizontally, and fewer marks = faster layout.
            ForEach(series) { s in
                let ma = movingAverage(for: s)
                let hasMa = !ma.isEmpty
                let pts = Self.downsample(visiblePoints(for: s), to: 400)

                ForEach(pts) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value(title, point.value),
                        series: .value("Metric", s.label)
                    )
                    .foregroundStyle(s.color.opacity(hasMa ? 0.25 : 1))
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: hasMa ? 1 : 2))

                    if showsPoints {
                        PointMark(
                            x: .value("Date", point.date),
                            y: .value(title, point.value)
                        )
                        .foregroundStyle(s.color.opacity(hasMa ? 0.3 : 1))
                        .symbolSize(30)
                    }
                }

                // 7-day moving average overlay (also downsampled for rendering)
                ForEach(Self.downsample(ma, to: 400)) { point in
                    LineMark(
                        x: .value("Date", point.date),
                        y: .value("\(title) avg", point.value),
                        series: .value("Metric", "\(s.label) avg")
                    )
                    .foregroundStyle(s.color)
                    .interpolationMethod(.monotone)
                    .lineStyle(StrokeStyle(lineWidth: 2.5))
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

            DietEventOverlayContent(events: visibleEvents)
        }
        .chartYScale(domain: .automatic(includesZero: false))
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine()
                AxisValueLabel(format: axisDateFormat)
            }
        }
        .chartYAxis { AxisMarks(position: .leading) }
        .accessibilityLabel(accessibilityLabel)
    }

    private var axisDateFormat: Date.FormatStyle {
        switch selectedRange {
        case .threeMonths, .sixMonths:
            return .dateTime.month(.abbreviated).day()
        case .oneYear, .all:
            return .dateTime.month(.abbreviated).year(.twoDigits)
        }
    }

    private var visibleEvents: [DietEvent] {
        guard let cutoff = rangeStart else { return events }
        return events.filter { ($0.endedOn ?? $0.startedOn) >= cutoff }
    }

    // MARK: - Legend

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
