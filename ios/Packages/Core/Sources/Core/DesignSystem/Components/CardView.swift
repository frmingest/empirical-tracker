import SwiftUI

/// A styled card surface. Mirrors the `Card` primitive used across the web dashboard.
/// Wrap any content in `CardView` to get the consistent background, border, corner radius,
/// and shadow that every panel uses.
public struct CardView<Content: View>: View {
    private let content: Content
    private let padding: EdgeInsets

    public init(
        padding: EdgeInsets = EdgeInsets(top: 16, leading: 16, bottom: 16, trailing: 16),
        @ViewBuilder content: () -> Content
    ) {
        self.padding = padding
        self.content = content()
    }

    public var body: some View {
        content
            .padding(padding)
            .background(Color.bgCard)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.borderCard, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.08), radius: 4, x: 0, y: 2)
    }
}

// MARK: - Preview

#Preview {
    CardView {
        VStack(alignment: .leading, spacing: 8) {
            Text("LDL-kolesterol").font(.headlineSmall).foregroundStyle(Color.textPrimary)
            Text("2.8 mmol/L").font(.numericMedium).foregroundStyle(Color.textPrimary)
        }
    }
    .padding()
    .background(Color.bgBase)
}
