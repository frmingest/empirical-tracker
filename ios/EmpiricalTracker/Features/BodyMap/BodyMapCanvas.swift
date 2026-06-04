import Biomarkers
import Core
import SwiftUI

/// Shared, fully responsive silhouette + hotspot-pin canvas used by both the
/// Dashboard body-map panel and the full-screen Body Map.
///
/// Scaling rules (the whole point of this view):
/// - The figure is **aspect-fit** into the available space, bounded by *both*
///   width and height, so it grows to use the vertical room on tall screens
///   instead of capping at a fixed width and floating in empty space.
/// - Every pin's size is derived from the figure width, so the pin-to-body
///   proportion stays constant across every device size.
/// - A single `maxFigureWidth` keeps the figure from becoming oversized on iPad.
struct BodyMapCanvas: View {
    let regions: [BodyRegion]
    /// Opacity of the silhouette fill (callers tune this to their background).
    var silhouetteOpacity: Double = 0.18
    /// Vertical space to reserve at the bottom (e.g. for a legend overlay) so
    /// the figure is centred in the *remaining* area and never overlaps it.
    var bottomReserve: CGFloat = 0
    var onSelect: (BodyRegion) -> Void

    /// Native aspect ratio (width ÷ height) of the BodySilhouette asset (1381×2000).
    private let aspect = 1381.0 / 2000.0
    /// Generous upper bound so the figure stays tasteful on iPad / large canvases.
    private let maxFigureWidth: CGFloat = 460
    /// Breathing room kept around the figure on every edge.
    private let edgeInset: CGFloat = 24

    var body: some View {
        GeometryReader { geo in
            let availableWidth  = max(geo.size.width  - edgeInset * 2, 1)
            let availableHeight = max(geo.size.height - edgeInset * 2 - bottomReserve, 1)

            // Aspect-fit: take whichever axis is the binding constraint.
            let figureWidth  = min(availableWidth, availableHeight * aspect, maxFigureWidth)
            let figureHeight = figureWidth / aspect

            let originX = (geo.size.width - figureWidth) / 2
            let originY = max((geo.size.height - bottomReserve - figureHeight) / 2, edgeInset)

            // Pin metrics scale with the figure so proportions hold everywhere.
            let pinDiameter = min(max(figureWidth * 0.13, 22), 46)

            ZStack(alignment: .topLeading) {
                Image("BodySilhouette")
                    .resizable()
                    .renderingMode(.template)
                    .scaledToFit()
                    .foregroundStyle(Color.textMuted.opacity(silhouetteOpacity))
                    .frame(width: figureWidth, height: figureHeight)
                    .position(
                        x: originX + figureWidth  / 2,
                        y: originY + figureHeight / 2
                    )

                ForEach(regions) { region in
                    BodyMapHotspotPin(region: region, diameter: pinDiameter) {
                        onSelect(region)
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

/// A single tappable region pin. Every dimension is derived from `diameter`
/// (handed down by `BodyMapCanvas`) so the pin scales with the silhouette.
struct BodyMapHotspotPin: View {
    let region: BodyRegion
    let diameter: CGFloat
    let onTap: () -> Void

    @State private var isPulsing = false

    private var assessment: MarkerSignals.Assessment { region.worstAssessment }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                // Pulse ring — only for markers that need attention.
                if assessment == .outOfRange || assessment == .watch {
                    Circle()
                        .fill(pinColor.opacity(0.22))
                        .frame(
                            width:  isPulsing ? diameter * 1.45 : diameter * 1.1,
                            height: isPulsing ? diameter * 1.45 : diameter * 1.1
                        )
                        .animation(
                            .easeInOut(duration: 1.3).repeatForever(autoreverses: true),
                            value: isPulsing
                        )
                }

                Circle()
                    .fill(pinColor)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: pinColor.opacity(0.45), radius: diameter * 0.18, x: 0, y: 2)

                // Resizable so the glyph scales with the pin (no fixed point size).
                Image(systemName: region.systemImage)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: diameter * 0.42, height: diameter * 0.42)
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
