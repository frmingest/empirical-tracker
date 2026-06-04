import Biomarkers
import Core
import SwiftUI

/// A single biomarker card in the dashboard grid.
/// Shows: name, latest value + unit, status badge, trend arrow, and a sparkline.
/// Mirrors the `BiomarkerCard` React component in `web/src/`.
struct BiomarkerCardView: View {
    let item: BiomarkerWithSeries

    private var latest: ResultPoint? { item.latestResult }
    private var info: BiomarkerInfo { item.biomarker }

    var body: some View {
        SoftCard(
            cornerRadius: 18,
            padding: EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        ) {
            VStack(alignment: .leading, spacing: 8) {
                nameRow
                valueRow
                sparkline
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityDescription)
    }

    // MARK: - Subviews

    private var nameRow: some View {
        Text(shortBiomarkerLabel(info.nameEn ?? info.nameNo))
            .font(.labelLarge)
            .foregroundStyle(Color.textSecondary)
            .lineLimit(1)
    }

    private var valueRow: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            if let point = latest {
                Text(formattedValue(point.value))
                    .font(.numericMedium)
                    .foregroundStyle(Color.textPrimary)
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)

                if let unit = info.unit {
                    Text(unit)
                        .font(.labelSmall)
                        .foregroundStyle(Color.textMuted)
                }

                Spacer(minLength: 4)

                trendIcon
                StatusBadgeView(inRange: point.inRange, compact: true)
            } else {
                Text("—")
                    .font(.numericMedium)
                    .foregroundStyle(Color.textMuted)
                Spacer()
                StatusBadgeView(status: .unknown, compact: true)
            }
        }
    }

    @ViewBuilder
    private var trendIcon: some View {
        switch item.trend {
        case .rising:
            Image(systemName: "arrow.up.right")
                .font(.labelSmall)
                .foregroundStyle(trendColor)
        case .falling:
            Image(systemName: "arrow.down.right")
                .font(.labelSmall)
                .foregroundStyle(trendColor)
        case .stable:
            EmptyView()
        }
    }

    private var sparkline: some View {
        SparklineView(
            series: item.series,
            refLow: info.refLow,
            refHigh: info.refHigh,
            refType: info.refType
        )
    }

    // MARK: - Helpers

    private func formattedValue(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }

    private var trendColor: Color {
        guard let point = latest else { return .textMuted }
        // Rising out of range = bad; rising toward range = neutral; etc.
        return point.inRange == false ? .outRange : .textMuted
    }

    private var accessibilityDescription: String {
        let name = info.nameEn ?? info.nameNo
        guard let point = latest else { return "\(name): no data" }
        let unit = info.unit ?? ""
        let rangeLabel: String
        switch point.inRange {
        case .some(true):  rangeLabel = "in range"
        case .some(false): rangeLabel = "out of range"
        case .none:        rangeLabel = "no reference range"
        }
        let trendLabel: String
        switch item.trend {
        case .rising:  trendLabel = ", trending up"
        case .falling: trendLabel = ", trending down"
        case .stable:  trendLabel = ""
        }
        return "\(name): \(formattedValue(point.value)) \(unit), \(rangeLabel)\(trendLabel)"
    }
}

// MARK: - Preview

#Preview {
    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 12) {
        ForEach(MockData.biomarkerSeries.prefix(4)) { item in
            BiomarkerCardView(item: item)
        }
    }
    .padding()
    .background(Color.bgBase)
}
