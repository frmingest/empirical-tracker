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
        GeometryReader { geo in
            let figureWidth  = min(geo.size.width * 0.52, 200)
            let figureHeight = figureWidth * 2.4
            let originX      = (geo.size.width  - figureWidth)  / 2
            let originY      = max((geo.size.height - figureHeight) / 2, 20)

            ZStack(alignment: .topLeading) {
                // Silhouette
                HumanBodySilhouette()
                    .fill(Color.textMuted.opacity(0.18))
                    .frame(width: figureWidth, height: figureHeight)
                    .position(
                        x: originX + figureWidth  / 2,
                        y: originY + figureHeight / 2
                    )

                // Hotspot pins
                ForEach(vm.regions) { region in
                    DashboardHotspotPin(region: region) {
                        selectedRegion = region
                    }
                    .position(
                        x: originX + figureWidth  * region.relativeX,
                        y: originY + figureHeight * region.relativeY
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .overlay(alignment: .bottom) {
                BodyMapLegendView()
                    .padding(.bottom, 16)
            }
        }
        .background(Color.bgBase)
    }
}

// MARK: - Hotspot pin

private struct DashboardHotspotPin: View {
    let region: BodyRegion
    let onTap: () -> Void

    @State private var isPulsing = false

    private var assessment: MarkerSignals.Assessment { region.worstAssessment }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                if assessment == .outOfRange || assessment == .watch {
                    Circle()
                        .fill(pinColor.opacity(0.22))
                        .frame(width: isPulsing ? 40 : 30, height: isPulsing ? 40 : 30)
                        .animation(
                            .easeInOut(duration: 1.3).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                }

                Circle()
                    .fill(pinColor)
                    .frame(width: 28, height: 28)
                    .shadow(color: pinColor.opacity(0.45), radius: 5, x: 0, y: 2)

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
