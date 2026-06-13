import Biomarkers
import Core
import SwiftUI

/// Interactive body map showing biomarker regions as tappable areas directly
/// over the relevant anatomy. Each area's outline color reflects the
/// worst-case assessment across all markers in that region. Tapping pushes
/// `OrganDetailView` with the organ illustration and trend graphs.
struct BodyMapView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var viewModel: BodyMapViewModel?
    @State private var selectedRegion: BodyRegion?
    @State private var selectedMarker: BiomarkerWithSeries?

    var body: some View {
        NavigationStack {
            ZStack {
                Color.bgBase.ignoresSafeArea()

                if let vm = viewModel {
                    if vm.isLoading {
                        LoadingView(message: "Loading biomarkers…")
                    } else {
                        bodyCanvas(vm)
                            .overlay(alignment: .bottom) {
                                LegendView()
                                    .padding(.bottom, 24)
                            }
                    }
                } else {
                    LoadingView(message: "Loading biomarkers…")
                }
            }
            .navigationTitle("Body Map")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(String(localized: "common.done")) { dismiss() }
                        .foregroundStyle(Color.accent)
                }
            }
            .navigationDestination(item: $selectedMarker) { marker in
                BiomarkerDetailView(initialMarker: marker)
            }
            .navigationDestination(item: $selectedRegion) { region in
                OrganDetailView(region: region) { marker in
                    selectedMarker = marker
                }
            }
        }
        .task {
            if viewModel == nil {
                viewModel = BodyMapViewModel(biomarkersRepo: env.biomarkers)
            }
            await viewModel?.load()
        }
        .alert(
            "Error",
            isPresented: Binding(
                get: { viewModel?.errorMessage != nil },
                set: { if !$0 { viewModel?.errorMessage = nil } }
            )
        ) {
            Button(String(localized: "common.ok"), role: .cancel) {}
        } message: {
            Text(viewModel?.errorMessage ?? "")
        }
    }

    // MARK: - Body canvas

    private func bodyCanvas(_ vm: BodyMapViewModel) -> some View {
        BodyMapCanvas(
            regions: vm.regions,
            biologicalSex: env.userProfile.biologicalSex,
            silhouetteOpacity: 0.22,
            bottomReserve: 84
        ) { region in
            selectedRegion = region
        }
    }
}

// MARK: - Legend

private struct LegendView: View {
    var body: some View {
        HStack(spacing: 16) {
            LegendItem(color: .inRange,  label: "In range")
            LegendItem(color: .orange,   label: "Watch")
            LegendItem(color: .outRange, label: "Out of range")
            LegendItem(color: Color.textMuted, label: "No data")
        }
        .font(.labelSmall)
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

private struct LegendItem: View {
    let color: Color
    let label: String

    var body: some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 8, height: 8)
            Text(label).foregroundStyle(Color.textSecondary)
        }
    }
}

// MARK: - Preview

#Preview {
    BodyMapView()
        .environment(AppEnvironment.preview())
}
