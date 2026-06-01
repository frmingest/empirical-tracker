import Biomarkers
import Core
import SwiftUI

/// Horizontal scrolling filter bar for diet focus selection.
/// Matches the web dashboard's diet toggle row.
struct DietFilterView: View {
    let currentFocus: DietFocus
    let onSelect: (DietFocus) async -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(dietOptions) { option in
                    FilterChip(
                        label: option.label,
                        isSelected: currentFocus == option.key
                    ) {
                        Task { await onSelect(option.key) }
                    }
                    .accessibilityHint(option.description)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Filter chip

private struct FilterChip: View {
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.labelLarge)
                .foregroundStyle(isSelected ? Color.bgBase : Color.textSecondary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accent : Color.bgCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .strokeBorder(isSelected ? Color.clear : Color.borderCard, lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        DietFilterView(currentFocus: .all) { _ in }
        DietFilterView(currentFocus: .carnivore) { _ in }
        DietFilterView(currentFocus: .custom) { _ in }
    }
    .padding(.vertical)
    .background(Color.bgBase)
}
