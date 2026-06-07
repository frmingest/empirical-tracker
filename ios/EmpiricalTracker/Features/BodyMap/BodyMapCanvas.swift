import Biomarkers
import Core
import SwiftUI

/// Shared, fully responsive silhouette + hotspot-pin canvas used by both the
/// Dashboard body-map panel and the full-screen Body Map.
///
/// Layout idea: the body itself is a small target, so the pins are *not* drawn
/// on the anatomy (where they overlap and crowd). Instead each pin is parked in
/// the open margin beside the figure — left or right per `region.side` — and a
/// thin leader line connects it back to a small status-coloured dot at the
/// region's anatomical anchor on the body.
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
    /// When set, only regions whose status matches stay fully opaque; the rest
    /// dim back. Driven by the dashboard's status-summary chips so tapping a
    /// status spotlights exactly those pins on the body.
    var highlightedAssessment: MarkerSignals.Assessment? = nil
    var onSelect: (BodyRegion) -> Void

    /// Native aspect ratio (width ÷ height) of the BodySilhouette asset (1381×2000).
    private let aspect = 1381.0 / 2000.0
    /// Generous upper bound so the figure stays tasteful on iPad / large canvases.
    private let maxFigureWidth: CGFloat = 460
    /// Breathing room kept around the figure on every edge.
    private let edgeInset: CGFloat = 24

    /// The BodySilhouette asset has transparent padding around the figure: the
    /// *visible body* occupies only this sub-rect of the image (measured from the
    /// asset's alpha channel). Region coordinates are authored body-relative
    /// (0–1 across the body itself), so they must be mapped through this box to
    /// land on the right anatomy instead of out in the empty padding.
    private let bodyMinX: CGFloat = 0.248
    private let bodyMaxX: CGFloat = 0.791
    private let bodyMinY: CGFloat = 0.066
    private let bodyMaxY: CGFloat = 0.934

    // Cache placement math so it only recalculates when canvas size changes.
    @State private var cachedPlacements: [PinPlacement] = []
    @State private var cachedSize: CGSize = .zero
    @State private var cachedBottomReserve: CGFloat = -1

    var body: some View {
        GeometryReader { geo in
            let size = geo.size

            // Recompute geometry only when layout inputs change.
            let availableWidth  = max(size.width  - edgeInset * 2, 1)
            let availableHeight = max(size.height - edgeInset * 2 - bottomReserve, 1)
            let figureWidth  = min(availableWidth, availableHeight * aspect, maxFigureWidth)
            let figureHeight = figureWidth / aspect
            let originX = (size.width  - figureWidth)  / 2
            let originY = max((size.height - bottomReserve - figureHeight) / 2, edgeInset)
            let bodyWidth   = figureWidth * (bodyMaxX - bodyMinX)
            let pinDiameter = min(max(bodyWidth * 0.11, 11), 22)

            let placements: [PinPlacement] = {
                if size == cachedSize && bottomReserve == cachedBottomReserve && !cachedPlacements.isEmpty {
                    return cachedPlacements
                }
                return makePlacements(
                    canvasSize: size,
                    originX: originX, originY: originY,
                    figureWidth: figureWidth, figureHeight: figureHeight,
                    pinDiameter: pinDiameter
                )
            }()

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

                // Leader lines + anatomical anchor dots, drawn behind the pins.
                // Live region lookup ensures year-filter changes (which mutate
                // region items/assessments without changing canvas geometry) are
                // reflected without invalidating the placement cache.
                Canvas { ctx, _ in
                    for placement in placements {
                        let live = regions.first { $0.id == placement.region.id } ?? placement.region
                        drawConnector(&ctx, placement: placement, liveRegion: live,
                                      pinDiameter: pinDiameter, dimmed: isDimmed(live))
                    }
                }
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)

                ForEach(placements) { placement in
                    let live = regions.first { $0.id == placement.region.id } ?? placement.region
                    let dimmed = isDimmed(live)
                    BodyMapHotspotPin(region: live, diameter: pinDiameter) {
                        onSelect(live)
                    }
                    .position(placement.pin)
                    .opacity(dimmed ? 0.22 : 1)
                    .animation(.easeInOut(duration: 0.2), value: dimmed)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .onChange(of: size) { _, newSize in
                cachedSize = newSize
                cachedBottomReserve = bottomReserve
                cachedPlacements = makePlacements(
                    canvasSize: newSize,
                    originX: originX, originY: originY,
                    figureWidth: figureWidth, figureHeight: figureHeight,
                    pinDiameter: pinDiameter
                )
            }
            .onAppear {
                if cachedPlacements.isEmpty {
                    cachedSize = size
                    cachedBottomReserve = bottomReserve
                    cachedPlacements = makePlacements(
                        canvasSize: size,
                        originX: originX, originY: originY,
                        figureWidth: figureWidth, figureHeight: figureHeight,
                        pinDiameter: pinDiameter
                    )
                }
            }
        }
    }

    /// A region dims when a status is spotlighted and it isn't that status.
    private func isDimmed(_ region: BodyRegion) -> Bool {
        guard let highlighted = highlightedAssessment else { return false }
        return region.worstAssessment.legendOrder != highlighted.legendOrder
    }

    // MARK: - Placement

    /// A resolved pin: where it's parked in the margin (`pin`) and where its
    /// leader line points on the body (`anchor`), both in canvas coordinates.
    private struct PinPlacement: Identifiable {
        let region: BodyRegion
        let anchor: CGPoint
        let pin: CGPoint
        var id: String { region.id }
    }

    /// Build the two margin columns. Each side's pins are ordered by anatomical
    /// height and then de-overlapped with a minimum vertical spacing so the
    /// column stays legible even when several anchors sit close together.
    private func makePlacements(
        canvasSize: CGSize,
        originX: CGFloat, originY: CGFloat,
        figureWidth: CGFloat, figureHeight: CGFloat,
        pinDiameter: CGFloat
    ) -> [PinPlacement] {
        let hitSize = max(pinDiameter * 1.45, 44)

        let bodyLeftX  = originX + figureWidth * bodyMinX
        let bodyRightX = originX + figureWidth * bodyMaxX

        // Park each column in the centre of its margin, but clamp so the whole
        // pin (and its tap target) stays on-screen and clear of the figure.
        let leftColumnX = clamp(bodyLeftX / 2,
                                min: hitSize / 2 + 2,
                                max: bodyLeftX - hitSize * 0.35)
        let rightColumnX = clamp((bodyRightX + canvasSize.width) / 2,
                                 min: bodyRightX + hitSize * 0.35,
                                 max: canvasSize.width - hitSize / 2 - 2)

        let topBound    = originY + hitSize / 2
        let bottomBound = originY + figureHeight - hitSize / 2
        let spacing     = max(hitSize * 0.95, pinDiameter * 1.7)

        func column(_ regions: [BodyRegion], x: CGFloat) -> [PinPlacement] {
            // Anatomical anchor for each region, sorted top→bottom.
            let anchored = regions.map { region -> (BodyRegion, CGPoint) in
                let frameX = bodyMinX + region.relativeX * (bodyMaxX - bodyMinX)
                let frameY = bodyMinY + region.relativeY * (bodyMaxY - bodyMinY)
                let anchor = CGPoint(
                    x: originX + figureWidth  * frameX,
                    y: originY + figureHeight * frameY
                )
                return (region, anchor)
            }
            .sorted { $0.1.y < $1.1.y }

            // Seed each pin at its anchor height, then push down to honour the
            // minimum spacing; if the column overruns the bottom, lift it back up.
            var ys = anchored.map { clamp($0.1.y, min: topBound, max: bottomBound) }
            for i in ys.indices where i > 0 {
                ys[i] = max(ys[i], ys[i - 1] + spacing)
            }
            if let last = ys.last, last > bottomBound {
                let overflow = last - bottomBound
                for i in ys.indices { ys[i] = max(ys[i] - overflow, topBound) }
                for i in ys.indices where i > 0 {
                    ys[i] = max(ys[i], ys[i - 1] + spacing)
                }
            }

            return zip(anchored, ys).map { entry, y in
                PinPlacement(region: entry.0, anchor: entry.1, pin: CGPoint(x: x, y: y))
            }
        }

        return column(regions.filter { $0.side == .left },  x: leftColumnX)
             + column(regions.filter { $0.side == .right }, x: rightColumnX)
    }

    /// Draw a dashed leader line from the pin's edge to a status-coloured dot at
    /// the anatomical anchor. Accepts liveRegion so colour reflects the current
    /// filter state rather than the cached placement's stale region snapshot.
    private func drawConnector(
        _ ctx: inout GraphicsContext,
        placement: PinPlacement,
        liveRegion: BodyRegion,
        pinDiameter: CGFloat,
        dimmed: Bool = false
    ) {
        let alpha = dimmed ? 0.22 : 1.0
        let pin = placement.pin
        let anchor = placement.anchor
        let dx = anchor.x - pin.x
        let dy = anchor.y - pin.y
        let dist = max(hypot(dx, dy), 0.0001)
        let ux = dx / dist
        let uy = dy / dist

        let dotRadius = max(pinDiameter * 0.16, 3)
        let start = CGPoint(x: pin.x + ux * (pinDiameter / 2 + 3),
                            y: pin.y + uy * (pinDiameter / 2 + 3))
        let end = CGPoint(x: anchor.x - ux * dotRadius,
                          y: anchor.y - uy * dotRadius)

        var line = Path()
        line.move(to: start)
        line.addLine(to: end)
        ctx.stroke(
            line,
            with: .color(Color.textMuted.opacity(0.45 * alpha)),
            style: StrokeStyle(lineWidth: 1, lineCap: .round, dash: [3, 3])
        )

        let color = liveRegion.worstAssessment.pinColor
        let dotRect = CGRect(x: anchor.x - dotRadius, y: anchor.y - dotRadius,
                             width: dotRadius * 2, height: dotRadius * 2)
        ctx.fill(Path(ellipseIn: dotRect), with: .color(color.opacity(alpha)))
        ctx.stroke(Path(ellipseIn: dotRect), with: .color(.white.opacity(0.65 * alpha)), lineWidth: 0.5)
    }
}

/// Clamp that tolerates an inverted `min`/`max` (which happens on very small
/// canvases where the margins collapse): rather than trapping on a bad
/// `ClosedRange`, it falls back to the midpoint so a pin still has a position.
private func clamp(_ value: CGFloat, min lower: CGFloat, max upper: CGFloat) -> CGFloat {
    if lower > upper { return (lower + upper) / 2 }
    return Swift.min(Swift.max(value, lower), upper)
}

// MARK: - Hotspot pin

/// A single tappable region pin. Every dimension is derived from `diameter`
/// (handed down by `BodyMapCanvas`) so the pin scales with the silhouette.
struct BodyMapHotspotPin: View {
    let region: BodyRegion
    let diameter: CGFloat
    let onTap: () -> Void

    private var assessment: MarkerSignals.Assessment { region.worstAssessment }

    private var hitSize: CGFloat { max(diameter * 1.45, 44) }

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Color.clear
                    .frame(width: hitSize, height: hitSize)

                Circle()
                    .fill(assessment.pinColor)
                    .frame(width: diameter, height: diameter)
                    .shadow(color: assessment.pinColor.opacity(0.45), radius: diameter * 0.18, x: 0, y: 2)

                Image(systemName: region.systemImage)
                    .resizable()
                    .scaledToFit()
                    .fontWeight(.semibold)
                    .frame(width: diameter * 0.42, height: diameter * 0.42)
                    .foregroundStyle(.white)
            }
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(region.label): \(accessibilityStatus)")
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
    /// Shared status colour used by both the margin pin and its anatomical
    /// anchor dot, so a region reads as one unit across the leader line.
    var pinColor: Color {
        switch self {
        case .outOfRange: return .outRange
        case .watch:      return .orange
        case .inRange:    return .inRange
        case .unknown:    return Color.textMuted
        }
    }

    // MARK: - Status legend metadata
    //
    // Single source of truth for how each status presents itself across the
    // dashboard: the live status-summary chips, the on-demand key popover, and
    // the spotlight-dimming all read from here so colour, icon and wording can
    // never drift apart. Colour is always paired with an icon + label (the
    // design-system rule that colour is never the only signal).

    /// Calm → attention ordering used for the summary row and key list, and as a
    /// stable identity for the spotlight selection.
    static let legendOrdered: [MarkerSignals.Assessment] = [.inRange, .watch, .outOfRange, .unknown]

    var legendOrder: Int {
        switch self {
        case .inRange:    return 0
        case .watch:      return 1
        case .outOfRange: return 2
        case .unknown:    return 3
        }
    }

    var legendLabel: String {
        switch self {
        case .inRange:    return "In range"
        case .watch:      return "Watch"
        case .outOfRange: return "Out of range"
        case .unknown:    return "No data"
        }
    }

    /// Filled SF Symbol that reads at small sizes inside a status chip.
    var legendIcon: String {
        switch self {
        case .inRange:    return "checkmark.circle.fill"
        case .watch:      return "exclamationmark.circle.fill"
        case .outOfRange: return "xmark.circle.fill"
        case .unknown:    return "minus.circle.fill"
        }
    }

    /// One-line plain-language meaning shown in the on-demand key popover.
    var legendDescription: String {
        switch self {
        case .inRange:    return "Within the healthy reference range."
        case .watch:      return "Near a limit or trending the wrong way."
        case .outOfRange: return "Outside the reference range — worth a look."
        case .unknown:    return "No recent results for this area yet."
        }
    }
}
