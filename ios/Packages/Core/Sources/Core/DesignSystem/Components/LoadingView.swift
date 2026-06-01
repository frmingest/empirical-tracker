import SwiftUI

/// Full-area loading placeholder with a pulsing skeleton effect.
public struct LoadingView: View {
    var message: String?

    public init(message: String? = nil) {
        self.message = message
    }

    public var body: some View {
        VStack(spacing: 16) {
            ProgressView()
                .progressViewStyle(.circular)
                .tint(Color.accent)
                .scaleEffect(1.4)
            if let message {
                Text(message)
                    .font(.bodySmall)
                    .foregroundStyle(Color.textMuted)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
    }
}

/// Single-row skeleton shimmer. Use inside list cells while data loads.
public struct SkeletonRow: View {
    @State private var animating = false

    public init() {}

    public var body: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 6)
                .frame(width: 40, height: 40)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 4).frame(height: 12)
                RoundedRectangle(cornerRadius: 4).frame(width: 80, height: 10)
            }
        }
        .foregroundStyle(Color.borderCard)
        .opacity(animating ? 0.4 : 1)
        .animation(.easeInOut(duration: 0.9).repeatForever(), value: animating)
        .onAppear { animating = true }
    }
}

#Preview {
    LoadingView(message: "Loading biomarkers…")
}
