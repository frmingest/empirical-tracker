import Foundation

/// App-level language override, persisted in `UserDefaults`.
/// Lets the user toggle EN ↔ NO regardless of their system language setting.
///
/// The toggle writes `AppleLanguages` to `UserDefaults` — Apple's standard override key.
/// The new language takes effect after the next launch; `SettingsView` shows a restart notice.
public enum AppLanguage: String, CaseIterable, Sendable {
    case system   = "system"
    case english  = "en"
    case norwegian = "nb"

    public var label: String {
        switch self {
        case .system:    return String(localized: "settings.language.system")
        case .english:   return "English"
        case .norwegian: return "Norsk"
        }
    }

    /// `Locale` used for number and date formatting (decimal comma in Norwegian).
    public var locale: Locale {
        switch self {
        case .system:    return .current
        case .english:   return Locale(identifier: "en_US")
        case .norwegian: return Locale(identifier: "nb_NO")
        }
    }
}
