import SwiftUI

/// Semantic color palette mirroring the CSS custom properties in `web/src/app/globals.css`.
/// Every color has a light and dark variant defined in `Assets.xcassets/Colors/`.
/// Usage: `Color.bgCard`, `Color.textPrimary`, etc. — never hardcode hex values.
public extension Color {

    // MARK: - Backgrounds
    /// Page-level background. CSS: --bg-base
    static let bgBase     = Color("BGBase",    bundle: .module)
    /// Card background. CSS: --bg-card
    static let bgCard     = Color("BGCard",    bundle: .module)
    /// Inputs, modals, popovers. CSS: --bg-elevated
    static let bgElevated = Color("BGElevated", bundle: .module)

    // MARK: - Text
    /// Primary body text. CSS: --text-primary
    static let textPrimary   = Color("TextPrimary",   bundle: .module)
    /// Secondary / supporting text. CSS: --text-secondary
    static let textSecondary = Color("TextSecondary", bundle: .module)
    /// Disabled, hints, placeholders. CSS: --text-muted
    static let textMuted     = Color("TextMuted",     bundle: .module)
    /// Low-contrast captions. CSS: --text-tertiary
    static let textTertiary  = Color("TextTertiary",  bundle: .module)

    // MARK: - Borders
    /// Card borders. CSS: --border-card
    static let borderCard   = Color("BorderCard",   bundle: .module)
    /// Dividers. CSS: --border-subtle
    static let borderSubtle = Color("BorderSubtle", bundle: .module)

    // MARK: - Semantic
    /// Primary interactive accent (blue). CSS: --color-accent
    static let accent    = Color("Accent",   bundle: .module)
    /// In-range indicator (emerald). CSS: --color-in-range
    static let inRange   = Color("InRange",  bundle: .module)
    /// Out-of-range indicator (rose). CSS: --color-out-range
    static let outRange  = Color("OutRange", bundle: .module)
}

// MARK: - UIColor convenience (for UIKit interop)

public extension UIColor {
    static let bgCard     = UIColor(named: "BGCard",     in: .module, compatibleWith: nil)
    static let accent     = UIColor(named: "Accent",     in: .module, compatibleWith: nil)
    static let inRange    = UIColor(named: "InRange",    in: .module, compatibleWith: nil)
    static let outRange   = UIColor(named: "OutRange",   in: .module, compatibleWith: nil)
}
