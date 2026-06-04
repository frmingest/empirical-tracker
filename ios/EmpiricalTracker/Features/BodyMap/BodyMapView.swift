import Biomarkers
import Core
import SwiftUI

/// Interactive body map showing biomarker regions as tappable hotspot pins.
/// Each pin's color reflects the worst-case assessment across all markers in
/// that region. Tapping opens a sheet listing those markers.
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
        }
        .task {
            if viewModel == nil {
                viewModel = BodyMapViewModel(biomarkersRepo: env.biomarkers)
            }
            await viewModel?.load()
        }
        .sheet(item: $selectedRegion) { region in
            BodyRegionSheet(region: region) { marker in
                selectedMarker = marker
            }
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
        GeometryReader { geo in
            let figureWidth  = geo.size.width * 0.52
            let figureHeight = figureWidth * 2.4
            let originX      = (geo.size.width  - figureWidth)  / 2
            let originY      = (geo.size.height - figureHeight) / 2

            ZStack(alignment: .topLeading) {
                // Body silhouette
                Image("BodySilhouette")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(Color.textMuted.opacity(0.22))
                    .frame(width: figureWidth, height: figureHeight)
                    .position(
                        x: originX + figureWidth  / 2,
                        y: originY + figureHeight / 2
                    )

                // Hotspot pins
                ForEach(vm.regions) { region in
                    HotspotPin(region: region) {
                        selectedRegion = region
                    }
                    .position(
                        x: originX + figureWidth  * region.relativeX,
                        y: originY + figureHeight * region.relativeY
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

// MARK: - Hotspot pin

private struct HotspotPin: View {
    let region: BodyRegion
    let onTap: () -> Void

    @State private var isPulsing = false

    private var assessment: MarkerSignals.Assessment { region.worstAssessment }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Pulse ring — only for out-of-range markers
                if assessment == .outOfRange || assessment == .watch {
                    Circle()
                        .fill(pinColor.opacity(0.25))
                        .frame(width: isPulsing ? 38 : 28, height: isPulsing ? 38 : 28)
                        .animation(
                            .easeInOut(duration: 1.2).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                }

                // Main pin circle
                Circle()
                    .fill(pinColor)
                    .frame(width: 26, height: 26)
                    .shadow(color: pinColor.opacity(0.5), radius: 4, x: 0, y: 2)

                // Icon
                Image(systemName: region.systemImage)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(region.label): \(accessibilityStatus)")
        .onAppear { isPulsing = true }
    }

    private var pinColor: Color {
        switch assessment {
        case .outOfRange: return .outRange
        case .watch:      return .orange
        case .inRange:    return .inRange
        case .unknown:    return Color.textMuted
        }
    }

    private var accessibilityStatus: String {
        guard !region.items.isEmpty else { return "no data" }
        switch assessment {
        case .outOfRange: return "out of range"
        case .watch:      return "watch"
        case .inRange:    return "in range"
        case .unknown:    return "unknown"
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
