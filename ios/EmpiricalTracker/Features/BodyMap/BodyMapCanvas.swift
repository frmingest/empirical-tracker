import Biomarkers
import Core
import SwiftUI

/// Shared, fully responsive silhouette + tappable organ-area canvas used by
/// both the Dashboard body-map panel and the full-screen Body Map.
///
/// The figure shown matches the user's `biologicalSex` (male/female; any
/// other value falls back to the male figure). Each `BodyRegion` defines a
/// rectangular `hitRect`, in body-relative coordinates, that sits directly
/// over the anatomy it represents — tapping it opens `OrganDetailView`
/// instead of the old margin pin + leader line.
///
/// Scaling rules (the whole point of this view):
/// - The figure is **aspect-fit** into the available space, bounded by *both*
///   width and height, so it grows to use the vertical room on tall screens
///   instead of capping at a fixed width and floating in empty space.
/// - Every hit-area's size is derived from the figure size, so the
///   area-to-body proportion stays constant across every device size.
/// - A single `maxFigureWidth` keeps the figure from becoming oversized on iPad.
struct BodyMapCanvas: View {
    let regions: [BodyRegion]
    /// Biological sex from the user's profile — selects the male or female
    /// figure. `nil`, `.other` and `.preferNotToSay` fall back to male.
    var biologicalSex: BiologicalSex? = nil
    /// Opacity of the silhouette fill (callers tune this to their background).
    var silhouetteOpacity: Double = 0.18
    /// Vertical space to reserve at the bottom (e.g. for a legend overlay) so
    /// the figure is centred in the *remaining* area and never overlaps it.
    var bottomReserve: CGFloat = 0
    /// When set, only regions whose status matches stay fully opaque; the rest
    /// dim back. Driven by the dashboard's status-summary chips so tapping a
    /// status spotlights exactly those hit-areas on the body.
    var highlightedAssessment: MarkerSignals.Assessment? = nil
    var onSelect: (BodyRegion) -> Void

    /// Native aspect ratio (width ÷ height) of the body silhouette assets (848×1264).
    private let aspect = 848.0 / 1264.0
    /// Generous upper bound so the figure stays tasteful on iPad / large canvases.
    private let maxFigureWidth: CGFloat = 460
    /// Breathing room kept around the figure on every edge.
    private let edgeInset: CGFloat = 24

    /// The body silhouette assets have transparent padding around the figure:
    /// the *visible body* occupies only this sub-rect of the image (measured
    /// from each asset's alpha channel; male and female bounds are close
    /// enough to share one box). `BodyRegion.hitRect` is authored relative to
    /// this box (0–1 across the body itself), so it lands on the right
    /// anatomy instead of out in the empty padding.
    private let bodyMinX: CGFloat = 0.26
    private let bodyMaxX: CGFloat = 0.74
    private let bodyMinY: CGFloat = 0.065
    private let bodyMaxY: CGFloat = 0.945

    private var silhouetteAssetName: String {
        biologicalSex == .female ? "BodySilhouetteFemale" : "BodySilhouetteMale"
    }

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            let availableWidth  = max(size.width  - edgeInset * 2, 1)
            let availableHeight = max(size.height - edgeInset * 2 - bottomReserve, 1)
            let figureWidth  = min(availableWidth, availableHeight * aspect, maxFigureWidth)
            let figureHeight = figureWidth / aspect
            let originX = (size.width  - figureWidth)  / 2
            let originY = max((size.height - bottomReserve - figureHeight) / 2, edgeInset)

            let bodyLeft   = originX + figureWidth  * bodyMinX
            let bodyTop    = originY + figureHeight * bodyMinY
            let bodyWidth  = figureWidth  * (bodyMaxX - bodyMinX)
            let bodyHeight = figureHeight * (bodyMaxY - bodyMinY)

            ZStack(alignment: .topLeading) {
                Image(silhouetteAssetName)
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
                    let live = regions.first { $0.id == region.id } ?? region
                    let rect = CGRect(
                        x: bodyLeft + live.hitRect.minX * bodyWidth,
                        y: bodyTop  + live.hitRect.minY * bodyHeight,
                        width:  live.hitRect.width  * bodyWidth,
                        height: live.hitRect.height * bodyHeight
                    )
                    OrganHitArea(region: live, dimmed: isDimmed(live)) {
                        onSelect(live)
                    }
                    .frame(width: rect.width, height: rect.height)
                    .position(x: rect.midX, y: rect.midY)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A region dims when a status is spotlighted and it isn't that status.
    private func isDimmed(_ region: BodyRegion) -> Bool {
        guard let highlighted = highlightedAssessment else { return false }
        return region.worstAssessment.legendOrder != highlighted.legendOrder
    }
}

// MARK: - Organ hit area

/// A tappable rectangle overlaid directly on the body region it represents.
/// Shown as a soft, rounded outline with the region's icon and a small
/// status-coloured dot so the user can see at a glance where to tap and what
/// that area's overall status is.
struct OrganHitArea: View {
    let region: BodyRegion
    var dimmed: Bool = false
    let onTap: () -> Void

    private var assessment: MarkerSignals.Assessment { region.worstAssessment }

    var body: some View {
        Button(action: onTap) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.textMuted.opacity(0.12))
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(assessment.pinColor.opacity(0.55), lineWidth: 1.5)
                )
                .overlay(alignment: .topTrailing) {
                    Circle()
                        .fill(assessment.pinColor)
                        .frame(width: 10, height: 10)
                        .padding(4)
                }
                .overlay {
                    Image(systemName: region.systemImage)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(Color.textSecondary)
                }
                .contentShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(.plain)
        .opacity(dimmed ? 0.22 : 1)
        .animation(.easeInOut(duration: 0.2), value: dimmed)
        .accessibilityLabel("\(region.label): \(accessibilityStatus)")
        .accessibilityHint("Opens \(region.label) details")
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

// MARK: - Status colour

extension MarkerSignals.Assessment {
    /// Shared status colour used by the hit-area outline and dot.
    var pinColor: Color {
        switch self {
        case .outOfRange: return .outRange
        case .watch:      return .orange
        case .inRange:    return .inRange
        case .unknown:    return Color.textMuted
        }
    }

    /// Stable rank used to compare statuses for spotlight-dimming.
    var legendOrder: Int {
        switch self {
        case .inRange:    return 0
        case .watch:      return 1
        case .outOfRange: return 2
        case .unknown:    return 3
        }
    }
}
