import SwiftUI

/// In-range / out-of-range / unknown indicator.
/// Uses both icon AND color so it's accessible to color-blind users.
/// Mirrors the `StatusBadge` React component.
public struct StatusBadgeView: View {
    public enum Status: Sendable {
        case inRange
        case outOfRange
        case watch       // large-step change or trending toward boundary
        case unknown     // ref_type == "none"
    }

    public let status: Status
    public var compact: Bool = false

    public init(status: Status, compact: Bool = false) {
        self.status = status
        self.compact = compact
    }

    public var body: some View {
        HStack(spacing: compact ? 3 : 5) {
            Image(systemName: iconName)
                .font(compact ? .labelSmall : .labelLarge)
            if !compact {
                Text(label)
                    .font(.labelMedium)
            }
        }
        .foregroundStyle(foregroundColor)
        .padding(.horizontal, compact ? 6 : 8)
        .padding(.vertical, compact ? 3 : 5)
        .background(foregroundColor.opacity(0.12))
        .clipShape(Capsule())
        .accessibilityLabel(label)
    }

    private var iconName: String {
        switch status {
        case .inRange:   return "checkmark.circle.fill"
        case .outOfRange: return "exclamationmark.circle.fill"
        case .watch:     return "eye.circle.fill"
        case .unknown:   return "minus.circle.fill"
        }
    }

    private var label: String {
        switch status {
        case .inRange:   return "In range"
        case .outOfRange: return "Out of range"
        case .watch:     return "Watch"
        case .unknown:   return "No ref"
        }
    }

    private var foregroundColor: Color {
        switch status {
        case .inRange:   return .inRange
        case .outOfRange: return .outRange
        case .watch:     return .accent
        case .unknown:   return .textMuted
        }
    }
}

// MARK: - Convenience

public extension StatusBadgeView {
    init(inRange: Bool?, compact: Bool = false) {
        switch inRange {
        case .some(true):  self.init(status: .inRange,    compact: compact)
        case .some(false): self.init(status: .outOfRange, compact: compact)
        case .none:        self.init(status: .unknown,    compact: compact)
        }
    }
}

// MARK: - Preview

#Preview {
    VStack(spacing: 12) {
        StatusBadgeView(status: .inRange)
        StatusBadgeView(status: .outOfRange)
        StatusBadgeView(status: .watch)
        StatusBadgeView(status: .unknown)
        HStack { StatusBadgeView(status: .inRange, compact: true); Text("compact") }
    }
    .padding()
    .background(Color.bgBase)
}
