import Biomarkers
import Core
import DietEvents
import SwiftUI

/// Plain-language intro for a biomarker category, shown above its charts so
/// non-medical readers understand what these markers mean for their body.
/// Shared by `CategoryGraphsView` and `OrganDetailView`.
struct CategorySummaryView: View {
    let category: BiomarkerCategory

    var body: some View {
        Label {
            Text(category.summary)
                .font(.bodySmall)
                .foregroundStyle(Color.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        } icon: {
            Image(systemName: "info.circle")
                .foregroundStyle(Color.accent)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.bgElevated, in: RoundedRectangle(cornerRadius: 10))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("About \(category.displayName): \(category.summary)")
    }
}

/// A single biomarker's trend chart, tappable to open its full history.
/// Shared by `CategoryGraphsView` and `OrganDetailView`.
struct BiomarkerChartCard: View {
    let item: BiomarkerWithSeries
    let dietEvents: [DietEvent]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            CardView {
                VStack(alignment: .leading, spacing: 12) {
                    header
                    BiomarkerTrendChart(marker: item, dietEvents: dietEvents)
                        .frame(height: 200)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens full history")
    }

    private var header: some View {
        let info = item.biomarker
        return HStack(alignment: .firstTextBaseline, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(shortBiomarkerLabel(info.nameEn ?? info.nameNo))
                    .font(.headlineSmall)
                    .foregroundStyle(Color.textPrimary)
                    .lineLimit(1)
                if let latest = item.latestResult {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(formattedValue(latest.value))
                            .font(.numericMedium)
                            .foregroundStyle(Color.textPrimary)
                        if let unit = info.unit {
                            Text(unit)
                                .font(.labelSmall)
                                .foregroundStyle(Color.textMuted)
                        }
                    }
                }
            }
            Spacer(minLength: 8)
            StatusBadgeView(status: badgeStatus)
            Image(systemName: "chevron.right")
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
        }
    }

    private var badgeStatus: StatusBadgeView.Status {
        switch MarkerSignals.assessment(for: item) {
        case .inRange:    return .inRange
        case .outOfRange: return .outOfRange
        case .watch:      return .watch
        case .unknown:    return .unknown
        }
    }

    private func formattedValue(_ v: Double) -> String {
        if v == v.rounded() && abs(v) < 1_000 {
            return String(format: "%.0f", v)
        }
        return String(format: "%.1f", v)
    }
}
