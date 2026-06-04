import Biomarkers
import Core
import SwiftUI

/// Inline body-map panel rendered inside the Dashboard's NavigationStack.
/// Tapping a region pushes CategoryGraphsView rather than showing a modal sheet.
struct DashboardBodyMapView: View {
    @Environment(AppEnvironment.self) private var env

    var onSelectCategory: (BiomarkerCategory) -> Void
    var onSelectMarker: (BiomarkerWithSeries) -> Void

    @State private var viewModel: BodyMapViewModel?
    @State private var selectedRegion: BodyRegion?

    var body: some View {
        Group {
            if let vm = viewModel {
                if vm.isLoading {
                    LoadingView(message: "Loading biomarkers…")
                } else {
                    bodyCanvas(vm)
                }
            } else {
                LoadingView(message: "Loading biomarkers…")
            }
        }
        .task {
            if viewModel == nil {
                viewModel = BodyMapViewModel(biomarkersRepo: env.biomarkers)
            }
            await viewModel?.load()
        }
        .sheet(item: $selectedRegion) { region in
            BodyRegionSheet(region: region) { marker in
                onSelectMarker(marker)
            }
        }
    }

    // MARK: - Canvas

    private func bodyCanvas(_ vm: BodyMapViewModel) -> some View {
        BodyMapCanvas(
            regions: vm.regions,
            silhouetteOpacity: 0.18,
            bottomReserve: 72
        ) { region in
            selectedRegion = region
        }
        .overlay(alignment: .bottom) {
            BodyMapLegendView()
                .padding(.bottom, 16)
        }
        .background(Color.bgBase)
    }
}

// MARK: - Legend

struct BodyMapLegendView: View {
    var body: some View {
        HStack(spacing: 14) {
            BodyMapLegendItem(color: .inRange,      label: "In range")
            BodyMapLegendItem(color: .orange,       label: "Watch")
            BodyMapLegendItem(color: .outRange,     label: "Out of range")
            BodyMapLegendItem(color: Color.textMuted, label: "No data")
        }
        .font(.labelSmall)
        .padding(.horizontal, 18)
        .padding(.vertical, 11)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct BodyMapLegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Color.textSecondary)
        }
    }
}
