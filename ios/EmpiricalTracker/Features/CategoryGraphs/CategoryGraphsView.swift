import Account
import Biomarkers
import Core
import DietEvents
import SwiftUI

/// Per-category graph view — pushed when a category header is tapped on the
/// dashboard. Shows the full trend chart for every biomarker in the group and
/// lets the user hop straight to another category (chip rail + prev/next)
/// without returning to the dashboard.
///
/// Tapping a chart opens the marker's detail screen; that navigation is owned
/// by the dashboard's `NavigationStack` via the `onSelectMarker` callback, so a
/// single `BiomarkerWithSeries` destination drives the whole stack.
struct CategoryGraphsView: View {
    @Environment(AppEnvironment.self) private var env

    /// Category to show first; the user can switch from here.
    let initialCategory: BiomarkerCategory
    /// Push the marker detail screen (handled by the dashboard stack).
    let onSelectMarker: (BiomarkerWithSeries) -> Void

    @State private var category: BiomarkerCategory

    init(
        initialCategory: BiomarkerCategory,
        onSelectMarker: @escaping (BiomarkerWithSeries) -> Void
    ) {
        self.initialCategory = initialCategory
        self.onSelectMarker = onSelectMarker
        _category = State(initialValue: initialCategory)
    }

    // MARK: - Derived data

    /// Populated category buckets, honouring the active diet focus so this view
    /// mirrors what the dashboard shows.
    private var groups: [BiomarkerGroup] {
        let filtered = filterByDiet(
            env.biomarkers.results,
            diet: env.account.settings.diet,
            customMarkers: Set(env.account.settings.customMarkers)
        )
        return groupedByCategory(filtered)
    }

    private var currentGroup: BiomarkerGroup? {
        groups.first { $0.category == category }
    }

    private var orderedCategories: [BiomarkerCategory] {
        groups.map(\.category)
    }

    var body: some View {
        VStack(spacing: 0) {
            categoryRail
            Divider()
            if let group = currentGroup {
                graphs(for: group)
            } else {
                emptyState
            }
        }
        .background(Color.bgBase)
        .navigationTitle(category.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if env.dietEvents.events.isEmpty {
                await env.dietEvents.load()
            }
        }
    }

    // MARK: - Category switcher rail

    private var categoryRail: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(orderedCategories) { cat in
                        CategoryChip(
                            label: cat.displayName,
                            outOfRange: outOfRangeCount(in: cat),
                            isSelected: cat == category
                        ) {
                            withAnimation(.easeInOut(duration: 0.2)) { category = cat }
                        }
                        .id(cat)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
            .onChange(of: category) { _, newValue in
                withAnimation { proxy.scrollTo(newValue, anchor: .center) }
            }
        }
    }

    // MARK: - Graph list

    private func graphs(for group: BiomarkerGroup) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                categorySummary(for: group.category)
                ForEach(group.items) { item in
                    chartCard(item)
                }
                categoryStepper
                    .padding(.top, 8)
            }
            .padding(16)
            // Reset scroll to top when switching categories.
            .id(category)
        }
    }

    /// Plain-language intro for the active category, shown above the charts so
    /// non-medical readers understand what these markers mean for their body.
    private func categorySummary(for category: BiomarkerCategory) -> some View {
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

    private func chartCard(_ item: BiomarkerWithSeries) -> some View {
        Button {
            onSelectMarker(item)
        } label: {
            CardView {
                VStack(alignment: .leading, spacing: 12) {
                    chartHeader(item)
                    BiomarkerTrendChart(marker: item, dietEvents: events(for: item))
                        .frame(height: 200)
                }
            }
        }
        .buttonStyle(.plain)
        .accessibilityHint("Opens full history")
    }

    private func chartHeader(_ item: BiomarkerWithSeries) -> some View {
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
            StatusBadgeView(status: badgeStatus(item))
            Image(systemName: "chevron.right")
                .font(.labelSmall)
                .foregroundStyle(Color.textMuted)
        }
    }

    // MARK: - Prev / next stepper

    @ViewBuilder
    private var categoryStepper: some View {
        let order = orderedCategories
        if order.count > 1, let idx = order.firstIndex(of: category) {
            let prev = order[(idx - 1 + order.count) % order.count]
            let next = order[(idx + 1) % order.count]
            HStack {
                stepperButton(to: prev, systemImage: "chevron.left", labelKey: "Previous", trailing: false)
                Spacer()
                stepperButton(to: next, systemImage: "chevron.right", labelKey: "Next", trailing: true)
            }
        }
    }

    private func stepperButton(
        to target: BiomarkerCategory,
        systemImage: String,
        labelKey: LocalizedStringKey,
        trailing: Bool
    ) -> some View {
        Button {
            withAnimation(.easeInOut(duration: 0.2)) { category = target }
        } label: {
            HStack(spacing: 8) {
                if !trailing { Image(systemName: systemImage) }
                VStack(alignment: trailing ? .trailing : .leading, spacing: 1) {
                    Text(labelKey)
                        .font(.labelSmall)
                        .foregroundStyle(Color.textMuted)
                    Text(target.displayName)
                        .font(.bodyMedium)
                        .foregroundStyle(Color.textPrimary)
                }
                if trailing { Image(systemName: systemImage) }
            }
            .foregroundStyle(Color.textSecondary)
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(Color.bgCard, in: RoundedRectangle(cornerRadius: 10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(Color.borderCard, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: "chart.xyaxis.line",
            title: "No markers in this group",
            message: "Try a different diet focus or switch to All on the dashboard."
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Helpers

    private func events(for marker: BiomarkerWithSeries) -> [DietEvent] {
        guard
            let first = marker.series.first?.testedAt,
            let last = marker.series.last?.testedAt
        else { return [] }
        return env.dietEvents.events(overlapping: first, end: last)
    }

    private func outOfRangeCount(in cat: BiomarkerCategory) -> Int {
        groups.first { $0.category == cat }?
            .items.filter { $0.latestResult?.inRange == false }.count ?? 0
    }

    private func badgeStatus(_ marker: BiomarkerWithSeries) -> StatusBadgeView.Status {
        switch MarkerSignals.assessment(for: marker) {
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

// MARK: - Category chip

/// A pill in the category switcher rail. Mirrors the diet `FilterChip` styling,
/// with a small dot when the group has out-of-range markers.
private struct CategoryChip: View {
    let label: String
    let outOfRange: Int
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Text(label)
                    .font(.labelLarge)
                if outOfRange > 0 {
                    Circle()
                        .fill(isSelected ? Color.bgBase : Color.outRange)
                        .frame(width: 6, height: 6)
                }
            }
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
    let env = AppEnvironment.preview()
    env.biomarkers.results = MockData.biomarkerSeries
    return NavigationStack {
        CategoryGraphsView(initialCategory: .lipids) { _ in }
            .environment(env)
    }
}
