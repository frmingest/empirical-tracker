import SwiftUI
import WidgetKit

// MARK: - Provider

struct WeightTrendProvider: TimelineProvider {
    typealias Entry = WeightTrendEntry

    func placeholder(in context: Context) -> WeightTrendEntry {
        WeightTrendEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (WeightTrendEntry) -> Void) {
        let snap = WidgetDataReader.snapshot() ?? WidgetDataReader.placeholder()
        completion(WeightTrendEntry(date: Date(), snapshot: snap, isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WeightTrendEntry>) -> Void) {
        let snap = WidgetDataReader.snapshot() ?? WidgetDataReader.placeholder()
        let entry = WeightTrendEntry(date: Date(), snapshot: snap, isPlaceholder: false)
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Entry

struct WeightTrendEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

// MARK: - Widget

struct WeightTrendWidget: Widget {
    let kind = "WeightTrendWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WeightTrendProvider()) { entry in
            WeightTrendWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Weight Trend")
        .description("Track your weight over the last 30 days.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct WeightTrendWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: WeightTrendEntry

    private var weight: WeightSummary? { entry.snapshot.weight }

    var body: some View {
        if let w = weight {
            switch family {
            case .systemSmall: smallView(w)
            default:           mediumView(w)
            }
        } else {
            noDataView
        }
    }

    // MARK: Small

    private func smallView(_ w: WeightSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "scalemass.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.blue)
                Text("Weight")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(String(format: "%.1f", w.latestKg))
                .font(.system(size: 34, weight: .bold, design: .rounded))
                + Text(" kg")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)

            HStack(spacing: 4) {
                trendIcon(w.trend)
                Text(relativeDate(w.latestDate))
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            sparkline(w.series, height: 28)
        }
        .padding(14)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: Medium

    private func mediumView(_ w: WeightSummary) -> some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "scalemass.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.blue)
                    Text("Weight")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                (Text(String(format: "%.1f", w.latestKg))
                    .font(.system(size: 34, weight: .bold, design: .rounded))
                + Text(" kg")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary))

                HStack(spacing: 4) {
                    trendIcon(w.trend)
                    Text(relativeDate(w.latestDate))
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                if w.series.count >= 2 {
                    let delta = w.series.last!.kg - w.series.first!.kg
                    Text(String(format: "%+.1f kg (30 d)", delta))
                        .font(.system(size: 11))
                        .foregroundStyle(delta < 0 ? Color.green : delta > 0.5 ? Color.red : Color.secondary)
                }

                Spacer()
            }
            .frame(maxWidth: 110)

            sparkline(w.series, height: 80)
        }
        .padding(14)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: No-data

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "scalemass")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("No weight data")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Sub-views

    @ViewBuilder
    private func sparkline(_ series: [WeightPoint], height: CGFloat) -> some View {
        GeometryReader { geo in
            if series.count >= 2 {
                let minY = series.map(\.kg).min()! - 0.5
                let maxY = series.map(\.kg).max()! + 0.5
                let range = max(maxY - minY, 0.1)
                let w = geo.size.width
                let h = geo.size.height

                Path { path in
                    for (i, pt) in series.enumerated() {
                        let x = w * CGFloat(i) / CGFloat(series.count - 1)
                        let y = h - h * CGFloat((pt.kg - minY) / range)
                        if i == 0 { path.move(to: CGPoint(x: x, y: y)) }
                        else { path.addLine(to: CGPoint(x: x, y: y)) }
                    }
                }
                .stroke(Color.blue.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))

                // Latest point dot
                if let last = series.last {
                    let x = w
                    let y = h - h * CGFloat((last.kg - minY) / range)
                    Circle()
                        .fill(Color.blue)
                        .frame(width: 5, height: 5)
                        .position(x: x, y: y)
                }
            }
        }
        .frame(height: height)
    }

    private func trendIcon(_ trend: String) -> some View {
        let (symbol, color): (String, Color) = switch trend {
        case "rising":  ("arrow.up.right", .red)
        case "falling": ("arrow.down.right", .green)
        default:        ("arrow.right", .secondary)
        }
        return Image(systemName: symbol)
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(color)
    }

    private func relativeDate(_ date: Date) -> String {
        let cal = Calendar.current
        if cal.isDateInToday(date)     { return "Today" }
        if cal.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    WeightTrendWidget()
} timeline: {
    WeightTrendEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: false)
}

#Preview(as: .systemMedium) {
    WeightTrendWidget()
} timeline: {
    WeightTrendEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: false)
}
