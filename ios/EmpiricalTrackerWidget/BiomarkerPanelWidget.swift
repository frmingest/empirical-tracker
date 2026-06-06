import SwiftUI
import WidgetKit

// MARK: - Provider

struct BiomarkerPanelProvider: TimelineProvider {
    typealias Entry = BiomarkerPanelEntry

    func placeholder(in context: Context) -> BiomarkerPanelEntry {
        BiomarkerPanelEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (BiomarkerPanelEntry) -> Void) {
        let snap = WidgetDataReader.snapshot() ?? WidgetDataReader.placeholder()
        completion(BiomarkerPanelEntry(date: Date(), snapshot: snap, isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<BiomarkerPanelEntry>) -> Void) {
        let snap = WidgetDataReader.snapshot() ?? WidgetDataReader.placeholder()
        let entry = BiomarkerPanelEntry(date: Date(), snapshot: snap, isPlaceholder: false)
        // Reload in 1 h; the app also calls WidgetCenter.shared.reloadAllTimelines on data refresh.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Entry

struct BiomarkerPanelEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

// MARK: - Widget

struct BiomarkerPanelWidget: Widget {
    let kind = "BiomarkerPanelWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: BiomarkerPanelProvider()) { entry in
            BiomarkerPanelWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Biomarkers")
        .description("See your flagged blood markers at a glance.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

// MARK: - Views

struct BiomarkerPanelWidgetView: View {
    @Environment(\.widgetFamily) var family
    let entry: BiomarkerPanelEntry

    var body: some View {
        switch family {
        case .systemSmall: smallView
        default:           mediumView
        }
    }

    // MARK: Small — count badge + status ring

    private var smallView: some View {
        let bm = entry.snapshot.biomarkers
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                Image(systemName: "drop.fill")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(accentColor(bm))
                Text("Markers")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text("\(bm.outOfRangeCount)")
                .font(.system(size: 38, weight: .bold, design: .rounded))
                .foregroundStyle(accentColor(bm))

            Text("out of range")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)

            Spacer()

            statusBar(bm)
        }
        .padding(14)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: Medium — list of flagged markers

    private var mediumView: some View {
        let bm = entry.snapshot.biomarkers
        return HStack(alignment: .top, spacing: 12) {
            // Left column: summary counts
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 4) {
                    Image(systemName: "drop.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(accentColor(bm))
                    Text("Markers")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                VStack(alignment: .leading, spacing: 2) {
                    countRow(value: bm.outOfRangeCount, label: "Out of range", color: .red)
                    countRow(value: bm.watchCount,      label: "Watch",         color: .orange)
                    countRow(value: bm.inRangeCount,    label: "In range",      color: .green)
                }

                Spacer()

                Text("of \(bm.totalCount) markers")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
            .frame(maxWidth: 100)

            Divider()

            // Right column: flagged marker rows
            VStack(alignment: .leading, spacing: 0) {
                if bm.flaggedMarkers.isEmpty {
                    Spacer()
                    Text("All markers in range")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                    Spacer()
                } else {
                    ForEach(bm.flaggedMarkers) { marker in
                        markerRow(marker)
                        if marker.id != bm.flaggedMarkers.last?.id {
                            Divider().padding(.vertical, 3)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(14)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: - Sub-views

    private func markerRow(_ m: FlaggedMarkerEntry) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(m.isOutOfRange ? Color.red : Color.orange)
                .frame(width: 6, height: 6)
            Text(m.name)
                .font(.system(size: 12, weight: .medium))
                .lineLimit(1)
            Spacer()
            Text("\(m.value, specifier: "%.1f") \(m.unit)")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Text(m.trendSymbol)
                .font(.system(size: 11))
                .foregroundStyle(m.trend == "rising" ? .red : m.trend == "falling" ? .green : .secondary)
        }
    }

    private func countRow(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Text("\(value)")
                .font(.system(size: 16, weight: .bold, design: .rounded))
                .foregroundStyle(color)
                .frame(width: 28, alignment: .trailing)
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    private func statusBar(_ bm: BiomarkerSummary) -> some View {
        GeometryReader { geo in
            HStack(spacing: 2) {
                let total = max(bm.totalCount, 1)
                let inW   = geo.size.width * CGFloat(bm.inRangeCount)    / CGFloat(total)
                let watW  = geo.size.width * CGFloat(bm.watchCount)      / CGFloat(total)
                let outW  = geo.size.width * CGFloat(bm.outOfRangeCount) / CGFloat(total)
                RoundedRectangle(cornerRadius: 2).fill(Color.green).frame(width: max(inW, 2))
                RoundedRectangle(cornerRadius: 2).fill(Color.orange).frame(width: max(watW, 2))
                RoundedRectangle(cornerRadius: 2).fill(Color.red).frame(width: max(outW, 2))
            }
        }
        .frame(height: 4)
    }

    private func accentColor(_ bm: BiomarkerSummary) -> Color {
        if bm.outOfRangeCount > 0 { return .red }
        if bm.watchCount > 0      { return .orange }
        return .green
    }
}

// MARK: - Preview

#Preview(as: .systemSmall) {
    BiomarkerPanelWidget()
} timeline: {
    BiomarkerPanelEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: false)
}

#Preview(as: .systemMedium) {
    BiomarkerPanelWidget()
} timeline: {
    BiomarkerPanelEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: false)
}
