import SwiftUI

/// Anatomically-proportioned front-facing human body silhouette drawn with
/// bezier curves, scaled to fill any CGRect while preserving aspect.
struct HumanBodySilhouette: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let W = rect.width
        let H = rect.height

        func px(_ t: CGFloat) -> CGFloat { rect.minX + t * W }
        func py(_ t: CGFloat) -> CGFloat { rect.minY + t * H }
        func pt(_ x: CGFloat, _ y: CGFloat) -> CGPoint { CGPoint(x: px(x), y: py(y)) }

        // ── HEAD ──────────────────────────────────────────────────────────────
        // Slightly taller-than-wide oval, top 14.8 % of figure height.
        path.addEllipse(in: CGRect(
            x: px(0.355), y: py(0.000),
            width: W * 0.290, height: H * 0.148
        ))

        // ── BODY + ARMS + LEGS  (single closed clockwise path) ────────────────
        // Start: left edge of neck just below the chin.
        path.move(to: pt(0.420, 0.138))

        // Left neck edge → left shoulder slope
        path.addCurve(to: pt(0.185, 0.228),
                      control1: pt(0.378, 0.172),
                      control2: pt(0.280, 0.205))

        // Left shoulder tip → left upper-arm outer edge
        path.addCurve(to: pt(0.130, 0.272),
                      control1: pt(0.148, 0.238),
                      control2: pt(0.125, 0.250))

        // Left arm outer edge downward (slight bow outward at elbow)
        path.addCurve(to: pt(0.110, 0.530),
                      control1: pt(0.105, 0.365),
                      control2: pt(0.092, 0.458))
        path.addCurve(to: pt(0.108, 0.642),
                      control1: pt(0.115, 0.575),
                      control2: pt(0.100, 0.615))

        // Left hand bottom
        path.addCurve(to: pt(0.178, 0.670),
                      control1: pt(0.106, 0.664),
                      control2: pt(0.142, 0.672))

        // Left arm inner edge back up to armpit (slight bow inward at elbow)
        path.addCurve(to: pt(0.198, 0.488),
                      control1: pt(0.205, 0.625),
                      control2: pt(0.210, 0.558))
        path.addCurve(to: pt(0.205, 0.302),
                      control1: pt(0.196, 0.435),
                      control2: pt(0.200, 0.368))

        // Armpit curve into left chest
        path.addCurve(to: pt(0.228, 0.338),
                      control1: pt(0.205, 0.312),
                      control2: pt(0.212, 0.328))

        // Left chest → waist (curves gently inward)
        path.addCurve(to: pt(0.252, 0.452),
                      control1: pt(0.235, 0.384),
                      control2: pt(0.232, 0.420))

        // Waist to left hip (slight inward then outward flare)
        path.addCurve(to: pt(0.238, 0.502),
                      control1: pt(0.256, 0.472),
                      control2: pt(0.242, 0.490))
        path.addCurve(to: pt(0.222, 0.542),
                      control1: pt(0.230, 0.516),
                      control2: pt(0.222, 0.530))

        // Left hip down to left thigh start
        path.addCurve(to: pt(0.218, 0.570),
                      control1: pt(0.222, 0.552),
                      control2: pt(0.218, 0.560))

        // Left thigh outer going down
        path.addCurve(to: pt(0.232, 0.714),
                      control1: pt(0.212, 0.618),
                      control2: pt(0.220, 0.670))

        // Left knee (slight outward bulge)
        path.addCurve(to: pt(0.240, 0.744),
                      control1: pt(0.232, 0.724),
                      control2: pt(0.240, 0.734))

        // Left shin outer
        path.addCurve(to: pt(0.252, 0.888),
                      control1: pt(0.240, 0.790),
                      control2: pt(0.246, 0.840))

        // Left ankle & foot
        path.addLine(to: pt(0.240, 0.906))
        path.addCurve(to: pt(0.186, 0.935),
                      control1: pt(0.240, 0.924),
                      control2: pt(0.216, 0.935))
        path.addLine(to: pt(0.184, 0.960))
        path.addLine(to: pt(0.180, 1.000))
        path.addLine(to: pt(0.374, 1.000))
        path.addLine(to: pt(0.368, 0.952))
        path.addCurve(to: pt(0.354, 0.906),
                      control1: pt(0.366, 0.930),
                      control2: pt(0.360, 0.918))

        // Left leg inner going up
        path.addCurve(to: pt(0.370, 0.716),
                      control1: pt(0.348, 0.850),
                      control2: pt(0.360, 0.784))

        // Left thigh inner going up to crotch
        path.addCurve(to: pt(0.385, 0.594),
                      control1: pt(0.376, 0.680),
                      control2: pt(0.378, 0.638))

        // Crotch curve
        path.addCurve(to: pt(0.435, 0.574),
                      control1: pt(0.392, 0.562),
                      control2: pt(0.412, 0.554))
        path.addCurve(to: pt(0.565, 0.574),
                      control1: pt(0.450, 0.594),
                      control2: pt(0.550, 0.594))

        // Right thigh inner going down from crotch
        path.addCurve(to: pt(0.615, 0.594),
                      control1: pt(0.588, 0.554),
                      control2: pt(0.608, 0.562))
        path.addCurve(to: pt(0.630, 0.716),
                      control1: pt(0.622, 0.638),
                      control2: pt(0.624, 0.680))

        // Right leg inner down to ankle
        path.addCurve(to: pt(0.646, 0.906),
                      control1: pt(0.640, 0.784),
                      control2: pt(0.652, 0.850))

        // Right foot
        path.addCurve(to: pt(0.632, 0.952),
                      control1: pt(0.640, 0.918),
                      control2: pt(0.634, 0.930))
        path.addLine(to: pt(0.626, 1.000))
        path.addLine(to: pt(0.820, 1.000))
        path.addLine(to: pt(0.816, 0.960))
        path.addLine(to: pt(0.814, 0.935))
        path.addCurve(to: pt(0.760, 0.906),
                      control1: pt(0.784, 0.935),
                      control2: pt(0.760, 0.924))
        path.addLine(to: pt(0.748, 0.888))

        // Right shin outer going up
        path.addCurve(to: pt(0.760, 0.744),
                      control1: pt(0.754, 0.840),
                      control2: pt(0.760, 0.790))

        // Right knee
        path.addCurve(to: pt(0.768, 0.714),
                      control1: pt(0.760, 0.734),
                      control2: pt(0.768, 0.724))

        // Right thigh outer going up
        path.addCurve(to: pt(0.782, 0.570),
                      control1: pt(0.780, 0.670),
                      control2: pt(0.788, 0.618))
        path.addCurve(to: pt(0.778, 0.542),
                      control1: pt(0.782, 0.560),
                      control2: pt(0.778, 0.552))

        // Right hip up to waist
        path.addCurve(to: pt(0.762, 0.502),
                      control1: pt(0.778, 0.530),
                      control2: pt(0.770, 0.516))
        path.addCurve(to: pt(0.748, 0.452),
                      control1: pt(0.758, 0.490),
                      control2: pt(0.765, 0.472))

        // Right chest up to armpit
        path.addCurve(to: pt(0.772, 0.338),
                      control1: pt(0.768, 0.420),
                      control2: pt(0.765, 0.384))

        // Right armpit
        path.addCurve(to: pt(0.795, 0.302),
                      control1: pt(0.788, 0.328),
                      control2: pt(0.795, 0.312))

        // Right arm inner edge going down (slight inward bow at elbow)
        path.addCurve(to: pt(0.802, 0.488),
                      control1: pt(0.800, 0.368),
                      control2: pt(0.804, 0.435))
        path.addCurve(to: pt(0.822, 0.642),
                      control1: pt(0.790, 0.558),
                      control2: pt(0.795, 0.625))

        // Right hand bottom
        path.addCurve(to: pt(0.892, 0.670),
                      control1: pt(0.858, 0.672),
                      control2: pt(0.894, 0.664))

        // Right arm outer edge going up (slight outward bow)
        path.addCurve(to: pt(0.890, 0.530),
                      control1: pt(0.900, 0.615),
                      control2: pt(0.908, 0.575))
        path.addCurve(to: pt(0.870, 0.272),
                      control1: pt(0.908, 0.458),
                      control2: pt(0.895, 0.365))

        // Right shoulder
        path.addCurve(to: pt(0.815, 0.228),
                      control1: pt(0.875, 0.250),
                      control2: pt(0.852, 0.238))

        // Right shoulder → right neck edge
        path.addCurve(to: pt(0.580, 0.138),
                      control1: pt(0.720, 0.205),
                      control2: pt(0.622, 0.172))

        path.closeSubpath()

        return path
    }
}

#Preview {
    HumanBodySilhouette()
        .fill(Color.gray.opacity(0.25))
        .frame(width: 180, height: 432)
        .padding()
        .background(Color(.systemBackground))
}
