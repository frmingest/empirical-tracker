import SwiftUI

/// Controls the app's `ColorScheme`, persisted in `UserDefaults` via `SettingsStore`.
public enum AppTheme: String, CaseIterable, Sendable {
    case system
    case light
    case dark

    /// The `ColorScheme` to pass to `.preferredColorScheme(_:)`. `nil` means follow system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light:  return .light
        case .dark:   return .dark
        }
    }

    public var label: String {
        switch self {
        case .system: return String(localized: "settings.theme.system")
        case .light:  return String(localized: "settings.theme.light")
        case .dark:   return String(localized: "settings.theme.dark")
        }
    }

    public var accessibilityLabel: String {
        String(localized: "settings.theme.picker.a11y") + " " + label
    }
}
