import Account
import Biomarkers
import Core
import DietEvents
import SwiftUI

/// Pushed when the user taps an organ hit-area on the body map. Shows the
/// relevant organ illustration(s) followed by the trend graphs for every
/// biomarker category associated with that region.
struct OrganDetailView: View {
    @Environment(AppEnvironment.self) private var env

    let region: BodyRegion
    var onSelectMarker: (BiomarkerWithSeries) -> Void

    var body: some View {
        Group {
            if region.items.isEmpty {
                emptyState
            } else {
                content
            }
        }
        .navigationTitle(region.label)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            if env.dietEvents.events.isEmpty {
                await env.dietEvents.load()
            }
        }
    }

    // MARK: - Content

    private var content: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 16) {
                organHeader
                ForEach(region.categories) { category in
                    let items = region.items.filter {
                        biomarkerCategory(for: $0.biomarker.nameNo) == category
                    }
                    if !items.isEmpty {
                        CategorySummaryView(category: category)
                        ForEach(items) { item in
                            BiomarkerChartCard(item: item, dietEvents: events(for: item)) {
                                onSelectMarker(item)
                            }
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    /// The organ illustration(s) for this region, or a large glyph fallback
    /// when no dedicated illustration exists yet.
    private var organHeader: some View {
        SoftCard {
            if region.primaryOrganImage.isEmpty {
                Image(systemName: region.systemImage)
                    .font(.system(size: 56, weight: .medium))
                    .foregroundStyle(Color.accent)
                    .frame(maxWidth: .infinity, minHeight: 140)
            } else {
                HStack(spacing: 12) {
                    organImage(region.primaryOrganImage)
                    if let secondary = region.secondaryOrganImage {
                        organImage(secondary)
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 140)
            }
        }
    }

    private func organImage(_ assetName: String) -> some View {
        Image(assetName)
            .resizable()
            .renderingMode(.template)
            .scaledToFit()
            .foregroundStyle(Color.accent)
            .frame(maxHeight: 140)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        EmptyStateView(
            icon: region.systemImage,
            title: "No results yet",
            message: "Import a blood panel to see \(region.label) markers here."
        )
    }

    // MARK: - Helpers

    private func events(for marker: BiomarkerWithSeries) -> [DietEvent] {
        guard
            let first = marker.series.first?.testedAt,
            let last = marker.series.last?.testedAt
        else { return [] }
        return env.dietEvents.events(overlapping: first, end: last)
    }
}

// MARK: - Preview

#Preview {
    let env = AppEnvironment.preview()
    env.biomarkers.results = MockData.biomarkerSeries
    let vm = BodyMapViewModel(biomarkersRepo: env.biomarkers)
    let region = vm.regions.first { $0.id == "lipids_cbc" }!
    return NavigationStack {
        OrganDetailView(region: region) { _ in }
            .environment(env)
    }
}
