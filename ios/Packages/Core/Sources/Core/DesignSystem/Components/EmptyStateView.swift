import SwiftUI

/// Generic empty-state view with icon, title, body text, and an optional CTA button.
/// Used on the dashboard before first import, diary with no entries, etc.
public struct EmptyStateView: View {
    public let icon: String
    public let title: String
    public let message: String
    public let action: Action?

    public struct Action: Sendable {
        public let label: String
        public let handler: @MainActor () -> Void

        public init(label: String, handler: @MainActor @escaping () -> Void) {
            self.label = label
            self.handler = handler
        }
    }

    public init(
        icon: String,
        title: String,
        message: String,
        action: Action? = nil
    ) {
        self.icon = icon
        self.title = title
        self.message = message
        self.action = action
    }

    public var body: some View {
        VStack(spacing: 20) {
            Image(systemName: icon)
                .font(.system(size: 44))
                .foregroundStyle(Color.textMuted)
                .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text(title)
                    .font(.headlineMedium)
                    .foregroundStyle(Color.textPrimary)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.bodyMedium)
                    .foregroundStyle(Color.textSecondary)
                    .multilineTextAlignment(.center)
            }

            if let action {
                Button(action.label) { MainActor.assumeIsolated(action.handler) }
                    .buttonStyle(PrimaryButtonStyle())
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.bgBase)
    }
}

// MARK: - Primary Button Style

public struct PrimaryButtonStyle: ButtonStyle {
    public init() {}
    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.headlineSmall)
            .foregroundStyle(.white)
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .background(Color.accent.opacity(configuration.isPressed ? 0.8 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .animation(.easeOut(duration: 0.15), value: configuration.isPressed)
    }
}

#Preview {
    EmptyStateView(
        icon: "doc.text.magnifyingglass",
        title: "No blood tests yet",
        message: "Import your first .xlsx file from a Norwegian lab to get started.",
        action: .init(label: "Import file") { }
    )
}
