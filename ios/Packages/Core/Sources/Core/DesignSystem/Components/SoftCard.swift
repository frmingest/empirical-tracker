import SwiftUI

/// A large, softly-shadowed surface that defines the redesigned home / diary /
/// plan screens. Compared with `CardView` (a tight 12-pt radius + hairline border
/// used for the dense biomarker grid), `SoftCard` uses a wide corner radius and a
/// diffuse, borderless shadow to give the airy, rounded look of the new design
/// language: floating white cards on a light grey page.
public struct SoftCard<Content: View>: View {
    private let content: Content
    private let padding: EdgeInsets
    private let cornerRadius: CGFloat
    private let fill: Color

    public init(
        cornerRadius: CGFloat = 24,
        fill: Color = .bgCard,
        padding: EdgeInsets = EdgeInsets(top: 18, leading: 18, bottom: 18, trailing: 18),
        @ViewBuilder content: () -> Content
    ) {
        self.cornerRadius = cornerRadius
        self.fill = fill
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(fill)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .shadow(color: .black.opacity(0.06), radius: 16, x: 0, y: 8)
    }
}

// MARK: - PillChip

/// A capsule pill used by the redesigned category / filter rows. The selected
/// state mirrors the reference design — a tinted wash, a coloured ring and
/// coloured text — rather than a hard solid fill, so the row stays light and airy.
public struct PillChip: View {
    private let title: String
    private let isSelected: Bool
    private let tint: Color
    private let action: () -> Void

    public init(
        _ title: String,
        isSelected: Bool,
        tint: Color = .accent,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.isSelected = isSelected
        self.tint = tint
        self.action = action
    }

    public var body: some View {
        Button(action: action) {
            Text(title)
                .font(.headlineSmall)
                .foregroundStyle(isSelected ? tint : Color.textSecondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(isSelected ? tint.opacity(0.12) : Color.bgCard)
                .clipShape(Capsule())
                .overlay(
                    Capsule().strokeBorder(
                        isSelected ? tint.opacity(0.9) : Color.borderCard,
                        lineWidth: isSelected ? 1.5 : 1
                    )
                )
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

// MARK: - CircleIconBadge

/// A circular, tinted icon badge — the leading glyph used on the redesigned list
/// cards (diary meals, plan days, dashboard sections). Colour is always paired
/// with the SF Symbol so it is never the only signal (ADR-006).
public struct CircleIconBadge: View {
    private let systemName: String
    private let tint: Color
    private let size: CGFloat

    public init(_ systemName: String, tint: Color = .accent, size: CGFloat = 44) {
        self.systemName = systemName
        self.tint = tint
        self.size = size
    }

    public var body: some View {
        Image(systemName: systemName)
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.15), in: Circle())
            .accessibilityHidden(true)
    }
}

// MARK: - Preview

#Preview {
    ScrollView {
        VStack(spacing: 16) {
            HStack {
                PillChip("All", isSelected: true) {}
                PillChip("Lipids", isSelected: false) {}
                PillChip("Thyroid", isSelected: false) {}
            }
            SoftCard {
                HStack(spacing: 12) {
                    CircleIconBadge("drop.fill", tint: .accent)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Track water").font(.headlineMedium)
                        Text("Tap to start tracking.").font(.bodySmall).foregroundStyle(Color.textSecondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").foregroundStyle(Color.textMuted)
                }
            }
        }
        .padding()
    }
    .background(Color.bgBase)
}
