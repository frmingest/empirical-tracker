import SwiftUI

/// Anatomically-detailed front-facing human body silhouette.
/// Drawn in a 200 × 480 design space then scaled to fill any CGRect.
/// Includes individual fingers and toe bumps as sub-paths so the
/// silhouette reads like a medical reference illustration, not an icon.
struct HumanBodySilhouette: Shape {

    func path(in rect: CGRect) -> Path {
        // Scale from design space (200 × 480) to target rect
        let sX = rect.width  / 200
        let sY = rect.height / 480

        // Convert design-space point to screen point
        func pt(_ dx: CGFloat, _ dy: CGFloat) -> CGPoint {
            CGPoint(x: rect.minX + dx * sX, y: rect.minY + dy * sY)
        }

        var path = Path()

        // ── HEAD ────────────────────────────────────────────────────────
        // Round skull, slight jaw narrowing toward chin.
        path.move(to: pt(100, 5))
        path.addCurve(to: pt(136, 40),
                      control1: pt(122, 5),   control2: pt(136, 20))
        path.addCurve(to: pt(100, 83),
                      control1: pt(136, 62),  control2: pt(122, 81))
        path.addCurve(to: pt(64, 40),
                      control1: pt(78, 81),   control2: pt(64, 62))
        path.addCurve(to: pt(100, 5),
                      control1: pt(64, 20),   control2: pt(78, 5))
        path.closeSubpath()

        // ── BODY + ARMS + LEGS  (single clockwise outline) ──────────────
        //  Start: right edge of neck, just below chin.
        path.move(to: pt(110, 81))

        // Right neck → right shoulder slope
        path.addCurve(to: pt(116, 108),
                      control1: pt(112, 92),  control2: pt(115, 100))
        path.addCurve(to: pt(163, 123),
                      control1: pt(126, 112), control2: pt(148, 117))
        path.addCurve(to: pt(171, 130),
                      control1: pt(168, 124), control2: pt(171, 126))

        // ── Right arm OUTER edge going DOWN ──
        // Arm angles outward ~8° from vertical; slight bow at elbow.
        path.addCurve(to: pt(183, 202),
                      control1: pt(178, 152), control2: pt(185, 176))
        path.addCurve(to: pt(189, 278),
                      control1: pt(183, 232), control2: pt(190, 258))
        path.addCurve(to: pt(189, 298),
                      control1: pt(189, 286), control2: pt(190, 292))

        // Right palm outer → hand base (stub; fingers added separately)
        path.addCurve(to: pt(188, 313),
                      control1: pt(189, 303), control2: pt(189, 309))
        path.addCurve(to: pt(174, 316),
                      control1: pt(188, 319), control2: pt(181, 318))
        path.addCurve(to: pt(170, 308),
                      control1: pt(168, 315), control2: pt(169, 312))

        // ── Right arm INNER edge going UP ──
        path.addCurve(to: pt(166, 272),
                      control1: pt(169, 298), control2: pt(167, 286))
        path.addCurve(to: pt(158, 200),
                      control1: pt(164, 250), control2: pt(161, 226))
        path.addCurve(to: pt(148, 136),
                      control1: pt(155, 176), control2: pt(151, 155))

        // Right armpit curve → right chest
        path.addCurve(to: pt(153, 158),
                      control1: pt(146, 140), control2: pt(149, 148))

        // Right chest → waist (slight inward curve) → hip (flare out)
        path.addCurve(to: pt(150, 238),
                      control1: pt(157, 190), control2: pt(153, 218))
        path.addCurve(to: pt(155, 275),
                      control1: pt(149, 256), control2: pt(153, 265))

        // Right hip → right thigh outer
        path.addCurve(to: pt(158, 285),
                      control1: pt(156, 278), control2: pt(158, 281))

        // ── Right thigh → knee → shin OUTER edge going DOWN ──
        path.addCurve(to: pt(156, 360),
                      control1: pt(161, 320), control2: pt(159, 343))
        path.addCurve(to: pt(154, 374),
                      control1: pt(156, 366), control2: pt(155, 370))
        path.addCurve(to: pt(153, 436),
                      control1: pt(153, 398), control2: pt(154, 418))

        // Right ankle → right foot outer edge
        path.addCurve(to: pt(152, 447),
                      control1: pt(153, 440), control2: pt(153, 444))
        path.addCurve(to: pt(140, 455),
                      control1: pt(152, 453), control2: pt(147, 456))
        // Foot bottom (toes added as sub-paths below)
        path.addCurve(to: pt(116, 458),
                      control1: pt(134, 458), control2: pt(126, 460))
        path.addCurve(to: pt(107, 452),
                      control1: pt(110, 458), control2: pt(108, 456))
        path.addCurve(to: pt(107, 443),
                      control1: pt(106, 447), control2: pt(106, 444))
        path.addCurve(to: pt(116, 436),
                      control1: pt(108, 440), control2: pt(112, 437))

        // ── Right leg INNER edge going UP ──
        path.addCurve(to: pt(120, 420),
                      control1: pt(118, 432), control2: pt(119, 426))
        path.addCurve(to: pt(124, 372),
                      control1: pt(122, 404), control2: pt(123, 389))
        path.addCurve(to: pt(128, 358),
                      control1: pt(125, 366), control2: pt(126, 362))
        path.addCurve(to: pt(130, 283),
                      control1: pt(130, 330), control2: pt(131, 304))

        // ── Crotch ──
        path.addCurve(to: pt(100, 290),
                      control1: pt(128, 272), control2: pt(114, 287))
        path.addCurve(to: pt(70, 283),
                      control1: pt(86, 287),  control2: pt(72, 272))

        // ── Left leg INNER edge going DOWN ──
        path.addCurve(to: pt(72, 358),
                      control1: pt(69, 304),  control2: pt(70, 330))
        path.addCurve(to: pt(76, 372),
                      control1: pt(74, 362),  control2: pt(75, 366))
        path.addCurve(to: pt(80, 420),
                      control1: pt(77, 389),  control2: pt(78, 404))
        path.addCurve(to: pt(84, 436),
                      control1: pt(81, 426),  control2: pt(82, 432))

        // Left foot inner edge → foot bottom → outer edge
        path.addCurve(to: pt(93, 443),
                      control1: pt(88, 437),  control2: pt(92, 440))
        path.addCurve(to: pt(93, 452),
                      control1: pt(94, 444),  control2: pt(94, 447))
        path.addCurve(to: pt(84, 458),
                      control1: pt(92, 456),  control2: pt(90, 458))
        path.addCurve(to: pt(60, 458),
                      control1: pt(74, 460),  control2: pt(66, 458))
        path.addCurve(to: pt(48, 455),
                      control1: pt(53, 456),  control2: pt(48, 453))
        path.addCurve(to: pt(47, 447),
                      control1: pt(47, 453),  control2: pt(47, 450))

        // ── Left leg OUTER edge going UP ──
        path.addCurve(to: pt(47, 436),
                      control1: pt(46, 443),  control2: pt(46, 440))
        path.addCurve(to: pt(46, 374),
                      control1: pt(46, 418),  control2: pt(45, 397))
        path.addCurve(to: pt(44, 360),
                      control1: pt(45, 370),  control2: pt(45, 365))
        path.addCurve(to: pt(42, 285),
                      control1: pt(41, 343),  control2: pt(39, 320))

        // Left hip → waist → chest
        path.addCurve(to: pt(45, 275),
                      control1: pt(42, 281),  control2: pt(45, 278))
        path.addCurve(to: pt(50, 238),
                      control1: pt(47, 265),  control2: pt(51, 256))
        path.addCurve(to: pt(47, 158),
                      control1: pt(47, 218),  control2: pt(43, 190))

        // Left armpit → left arm INNER edge going DOWN
        path.addCurve(to: pt(52, 136),
                      control1: pt(51, 148),  control2: pt(54, 140))
        path.addCurve(to: pt(42, 200),
                      control1: pt(49, 155),  control2: pt(45, 176))
        path.addCurve(to: pt(34, 272),
                      control1: pt(39, 226),  control2: pt(36, 250))
        path.addCurve(to: pt(30, 308),
                      control1: pt(31, 286),  control2: pt(31, 298))

        // Left palm inner → hand base
        path.addCurve(to: pt(26, 316),
                      control1: pt(31, 312),  control2: pt(32, 315))
        path.addCurve(to: pt(12, 313),
                      control1: pt(19, 318),  control2: pt(15, 317))
        path.addCurve(to: pt(11, 298),
                      control1: pt(8, 311),   control2: pt(8, 304))

        // ── Left arm OUTER edge going UP ──
        path.addCurve(to: pt(11, 278),
                      control1: pt(10, 292),  control2: pt(10, 285))
        path.addCurve(to: pt(17, 202),
                      control1: pt(10, 258),  control2: pt(15, 232))
        path.addCurve(to: pt(29, 130),
                      control1: pt(15, 176),  control2: pt(22, 152))

        // Left shoulder → left neck
        path.addCurve(to: pt(37, 123),
                      control1: pt(29, 126),  control2: pt(32, 124))
        path.addCurve(to: pt(84, 108),
                      control1: pt(52, 117),  control2: pt(74, 112))
        path.addCurve(to: pt(90, 81),
                      control1: pt(85, 100),  control2: pt(88, 92))
        path.closeSubpath()

        // ── FINGERS ──────────────────────────────────────────────────────
        // Each finger: ellipse in local frame (x: -fw/2, y: 0, w: fw, h: fh),
        // rotated around its top-center, then translated to screen position.
        let fw = CGFloat(6) * sX
        let fh = CGFloat(24) * sY

        // Left hand — palm centre ≈ (19, 310) in design space
        // Thumb is on the body-side (higher x), pinky on the outer side (lower x).
        let leftFingers: [(dx: CGFloat, dy: CGFloat, angle: CGFloat)] = [
            (dx:  9, dy: 7, angle:  0.32),  // thumb
            (dx:  4, dy: 9, angle:  0.13),  // index
            (dx:  0, dy: 11, angle: 0.00),  // middle (longest)
            (dx: -4, dy: 9, angle: -0.13),  // ring
            (dx: -8, dy: 7, angle: -0.26),  // pinky
        ]
        addFingers(&path, fingers: leftFingers,
                   handX: 19, handY: 310, sX: sX, sY: sY,
                   origin: rect.origin, fw: fw, fh: fh)

        // Right hand (mirrored) — palm centre ≈ (181, 310)
        let rightFingers: [(dx: CGFloat, dy: CGFloat, angle: CGFloat)] = [
            (dx: -9, dy: 7, angle: -0.32),
            (dx: -4, dy: 9, angle: -0.13),
            (dx:  0, dy: 11, angle: 0.00),
            (dx:  4, dy: 9, angle:  0.13),
            (dx:  8, dy: 7, angle:  0.26),
        ]
        addFingers(&path, fingers: rightFingers,
                   handX: 181, handY: 310, sX: sX, sY: sY,
                   origin: rect.origin, fw: fw, fh: fh)

        // ── TOES ──────────────────────────────────────────────────────────
        // Five rounded bumps at the bottom of each foot.
        let tW = CGFloat(8.0) * sX   // toe width
        let tH = CGFloat(11.0) * sY  // toe height
        let toeY = rect.minY + 446 * sY

        // Left foot toes (centred roughly over the left foot, x = 33…73)
        let leftToeXs: [CGFloat] = [34, 43, 52, 60, 68]
        for tx in leftToeXs {
            path.addEllipse(in: CGRect(
                x: rect.minX + tx * sX - tW / 2,
                y: toeY - tH * 0.35,
                width: tW, height: tH
            ))
        }

        // Right foot toes (mirrored, x = 127…166)
        let rightToeXs: [CGFloat] = [132, 140, 148, 157, 166]
        for tx in rightToeXs {
            path.addEllipse(in: CGRect(
                x: rect.minX + tx * sX - tW / 2,
                y: toeY - tH * 0.35,
                width: tW, height: tH
            ))
        }

        return path
    }

    // MARK: - Helpers

    private func addFingers(
        _ path: inout Path,
        fingers: [(dx: CGFloat, dy: CGFloat, angle: CGFloat)],
        handX: CGFloat, handY: CGFloat,
        sX: CGFloat, sY: CGFloat,
        origin: CGPoint,
        fw: CGFloat, fh: CGFloat
    ) {
        for f in fingers {
            let cx = origin.x + (handX + f.dx) * sX
            let cy = origin.y + (handY + f.dy) * sY
            // Ellipse with top-centre at (0,0), pointing downward
            let fingerEllipse = Path(ellipseIn: CGRect(x: -fw / 2, y: 0, width: fw, height: fh))
            let transform = CGAffineTransform(rotationAngle: f.angle)
                .concatenating(CGAffineTransform(translationX: cx, y: cy))
            path.addPath(fingerEllipse, transform: transform)
        }
    }
}

// MARK: - Preview

#Preview {
    HumanBodySilhouette()
        .fill(Color.gray.opacity(0.30))
        .frame(width: 180, height: 432)
        .padding(24)
        .background(Color(.systemBackground))
}
