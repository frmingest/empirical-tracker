import Biomarkers
import Core
import SwiftUI

/// A section in the dashboard grid: category header + 2-column card grid.
struct CategorySectionView: View {
    let group: BiomarkerGroup
    let onTapCard: (BiomarkerWithSeries) -> Void
    /// Tapping the header opens the per-category graph view.
    var onTapHeader: ((BiomarkerCategory) -> Void)? = nil

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            sectionHeader
            LazyVGrid(columns: columns, spacing: 12) {
                ForEach(group.items) { item in
                    BiomarkerCardView(item: item)
                        .onTapGesture { onTapCard(item) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sectionHeader: some View {
        Button {
            onTapHeader?(group.category)
        } label: {
            HStack(spacing: 12) {
                CircleIconBadge(
                    group.category.iconName,
                    tint: group.category.tint,
                    size: 38
                )

                Text(group.category.displayName)
                    .font(.headlineLarge)
                    .foregroundStyle(Color.textPrimary)

                if onTapHeader != nil {
                    Image(systemName: "chevron.right")
                        .font(.labelLarge)
                        .foregroundStyle(Color.textMuted)
                }

                Spacer()

                outOfRangeCount
            }
            .padding(.horizontal, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(onTapHeader == nil)
        .accessibilityHint(onTapHeader != nil ? "Shows every graph in this group" : "")
    }

    @ViewBuilder
    private var outOfRangeCount: some View {
        let count = group.items.filter { $0.latestResult?.inRange == false }.count
        if count > 0 {
            HStack(spacing: 3) {
                Image(systemName: "exclamationmark.circle.fill")
                    .font(.labelSmall)
                Text("\(count)")
                    .font(.labelSmall)
            }
            .foregroundStyle(Color.outRange)
            .accessibilityLabel("\(count) out of range")
        }
    }
}

// MARK: - Category presentation (view layer)

private extension BiomarkerCategory {
    /// SF Symbol shown in the section's circular badge. View-layer only — keeps the
    /// domain model free of presentation concerns.
    var iconName: String {
        switch self {
        case .lipids:       return "drop.fill"
        case .cbc:          return "drop.triangle.fill"
        case .metabolic:    return "bolt.fill"
        case .thyroid:      return "shield.lefthalf.filled"
        case .renal:        return "drop.circle.fill"
        case .liver:        return "cross.case.fill"
        case .nutrients:    return "leaf.fill"
        case .electrolytes: return "atom"
        case .other:        return "circle.grid.2x2.fill"
        }
    }

    /// Accent tone for the badge. Paired with the icon, never colour-as-only-signal.
    var tint: Color {
        switch self {
        case .lipids:       return .mealBreakfast
        case .cbc:          return .outRange
        case .metabolic:    return .accent
        case .thyroid:      return .mealDinner
        case .renal:        return .mealLunch
        case .liver:        return .mealOther
        case .nutrients:    return .inRange
        case .electrolytes: return .mealSnack
        case .other:        return .textMuted
        }
    }
}

// MARK: - Preview

#Preview {
    let groups = groupedByCategory(MockData.biomarkerSeries)
    return ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(groups) { group in
                CategorySectionView(group: group, onTapCard: { _ in })
            }
        }
        .padding()
    }
    .background(Color.bgBase)
}
