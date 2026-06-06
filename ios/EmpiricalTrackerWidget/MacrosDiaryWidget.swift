import SwiftUI
import WidgetKit

// MARK: - Provider

struct MacrosProvider: TimelineProvider {
    typealias Entry = MacrosEntry

    func placeholder(in context: Context) -> MacrosEntry {
        MacrosEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: true)
    }

    func getSnapshot(in context: Context, completion: @escaping (MacrosEntry) -> Void) {
        let snap = WidgetDataReader.snapshot() ?? WidgetDataReader.placeholder()
        completion(MacrosEntry(date: Date(), snapshot: snap, isPlaceholder: context.isPreview))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<MacrosEntry>) -> Void) {
        let snap = WidgetDataReader.snapshot() ?? WidgetDataReader.placeholder()
        let entry = MacrosEntry(date: Date(), snapshot: snap, isPlaceholder: false)
        // Reload hourly; app calls reloadAllTimelines after each food diary save.
        let next = Calendar.current.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        completion(Timeline(entries: [entry], policy: .after(next)))
    }
}

// MARK: - Entry

struct MacrosEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot
    let isPlaceholder: Bool
}

// MARK: - Widget

struct MacrosDiaryWidget: Widget {
    let kind = "MacrosDiaryWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: MacrosProvider()) { entry in
            MacrosDiaryWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Today's Macros")
        .description("See today's protein, carbs and fat from your food diary.")
        .supportedFamilies([.systemMedium])
    }
}

// MARK: - View

struct MacrosDiaryWidgetView: View {
    let entry: MacrosEntry

    private var macros: MacroSummary? { entry.snapshot.macros }

    var body: some View {
        if let m = macros, Calendar.current.isDateInToday(m.date) {
            loadedView(m)
        } else {
            noDataView
        }
    }

    // MARK: Loaded

    private func loadedView(_ m: MacroSummary) -> some View {
        HStack(alignment: .top, spacing: 16) {
            // Kcal column
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.orange)
                    Text("Today")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Text(String(format: "%.0f", m.kcal))
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                + Text(" kcal")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .frame(maxWidth: 100)

            Divider()

            // Macro rings / bars
            VStack(alignment: .leading, spacing: 8) {
                macroRow(label: "Protein", value: m.proteinG, color: .blue,   unit: "g")
                macroRow(label: "Carbs",   value: m.carbsG,   color: .yellow, unit: "g")
                macroRow(label: "Fat",     value: m.fatG,     color: .orange, unit: "g")
            }
            .frame(maxWidth: .infinity)
        }
        .padding(14)
        .redacted(reason: entry.isPlaceholder ? .placeholder : [])
    }

    // MARK: No-data

    private var noDataView: some View {
        VStack(spacing: 8) {
            Image(systemName: "fork.knife")
                .font(.system(size: 24))
                .foregroundStyle(.secondary)
            Text("Log food to see today's macros")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding()
    }

    // MARK: - Sub-views

    private func macroRow(label: String, value: Double, color: Color, unit: String) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .leading)

            GeometryReader { geo in
                // Bar capped at a generous daily reference (protein 200g, carbs 300g, fat 150g)
                let maxRef: Double = label == "Protein" ? 200 : label == "Carbs" ? 300 : 150
                let fraction = min(value / maxRef, 1.0)
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color.opacity(0.18))
                    RoundedRectangle(cornerRadius: 3)
                        .fill(color)
                        .frame(width: geo.size.width * fraction)
                }
            }
            .frame(height: 8)

            Text(String(format: "%.0f%@", value, unit))
                .font(.system(size: 11, weight: .semibold))
                .frame(width: 40, alignment: .trailing)
        }
    }
}

// MARK: - Preview

#Preview(as: .systemMedium) {
    MacrosDiaryWidget()
} timeline: {
    MacrosEntry(date: Date(), snapshot: WidgetDataReader.placeholder(), isPlaceholder: false)
}
