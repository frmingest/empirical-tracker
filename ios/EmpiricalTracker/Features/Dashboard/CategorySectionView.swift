import Biomarkers
import Core
import SwiftUI

/// A section in the dashboard grid: category header + 2-column card grid.
struct CategorySectionView: View {
    let group: BiomarkerGroup
    let onTapCard: (BiomarkerWithSeries) -> Void

    private let columns = [GridItem(.flexible()), GridItem(.flexible())]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader
            LazyVGrid(columns: columns, spacing: 10) {
                ForEach(group.items) { item in
                    BiomarkerCardView(item: item)
                        .onTapGesture { onTapCard(item) }
                }
            }
        }
        .accessibilityElement(children: .contain)
    }

    private var sectionHeader: some View {
        HStack(spacing: 6) {
            Text(group.category.displayName)
                .font(.headlineSmall)
                .foregroundStyle(Color.textPrimary)

            Spacer()

            outOfRangeCount
        }
        .padding(.horizontal, 2)
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

// MARK: - Preview

#Preview {
    let groups = groupedByCategory(MockData.biomarkerSeries)
    return ScrollView {
        LazyVStack(alignment: .leading, spacing: 24) {
            ForEach(groups) { group in
                CategorySectionView(group: group) { _ in }
            }
        }
        .padding()
    }
    .background(Color.bgBase)
}
