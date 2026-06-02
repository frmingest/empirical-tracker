import Core
import SwiftUI

/// A single blood-draw session card on the panel timeline.
/// Shows draw date, source, result counts, and flagged marker names.
struct PanelCardView: View {
    let panel: Panel
    let flaggedMarkers: [String]

    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .long
        f.timeStyle = .none
        return f
    }()

    var body: some View {
        CardView(padding: EdgeInsets(top: 14, leading: 16, bottom: 14, trailing: 16)) {
            VStack(alignment: .leading, spacing: 10) {
                // Header row
                HStack(alignment: .firstTextBaseline) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(Self.dateFormatter.string(from: panel.testedAt))
                            .font(.headlineSmall)
                            .foregroundStyle(Color.textPrimary)
                        Text(panel.source)
                            .font(.labelMedium)
                            .foregroundStyle(Color.textMuted)
                    }
                    Spacer()
                    sourceIcon
                }

                // Result count chips
                HStack(spacing: 8) {
                    if let total = panel.resultCount {
                        countChip(value: total, label: "total", color: .textSecondary)
                    }
                    if let inRange = panel.inRangeCount {
                        countChip(value: inRange, label: "in range", color: .inRange)
                    }
                    if let outRange = panel.outRangeCount, outRange > 0 {
                        countChip(value: outRange, label: "flagged", color: .outRange)
                    }
                }

                // Flagged marker names
                if !flaggedMarkers.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Out of range")
                            .font(.labelSmall)
                            .foregroundStyle(Color.textMuted)
                        Text(flaggedMarkers.joined(separator: " · "))
                            .font(.bodySmall)
                            .foregroundStyle(Color.outRange)
                            .lineLimit(3)
                    }
                }
            }
        }
    }

    private var sourceIcon: some View {
        Image(systemName: "tablecells")
            .font(.labelLarge)
            .foregroundStyle(Color.textMuted)
            .accessibilityHidden(true)
    }

    private func countChip(value: Int, label: String, color: Color) -> some View {
        HStack(spacing: 3) {
            Text("\(value)")
                .font(.numericSmall)
                .foregroundStyle(color)
            Text(label)
                .font(.labelSmall)
                .foregroundStyle(color.opacity(0.8))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(color.opacity(0.1))
        .clipShape(Capsule())
    }
}
