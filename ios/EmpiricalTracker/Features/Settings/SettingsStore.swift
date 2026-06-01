import SwiftUI
import Observation

/// Persists user preferences (theme + language) via `UserDefaults`.
/// Observed app-wide through `AppEnvironment`.
@MainActor
@Observable
public final class SettingsStore {

    // MARK: - State

    public var theme: AppTheme {
        didSet { UserDefaults.standard.set(theme.rawValue, forKey: Keys.theme) }
    }

    public var language: AppLanguage {
        didSet {
            UserDefaults.standard.set(language.rawValue, forKey: Keys.language)
            applyLanguageOverride(language)
        }
    }

    // MARK: - Init

    public init() {
        let savedTheme    = UserDefaults.standard.string(forKey: Keys.theme)
        let savedLanguage = UserDefaults.standard.string(forKey: Keys.language)
        theme    = AppTheme(rawValue: savedTheme ?? "")       ?? .system
        language = AppLanguage(rawValue: savedLanguage ?? "") ?? .system
    }

    // MARK: - Private

    private enum Keys {
        static let theme    = "app.theme"
        static let language = "app.language"
    }

    /// Writes `AppleLanguages` — Apple's standard UserDefaults key for language override.
    /// The change is picked up on the next process launch.
    private func applyLanguageOverride(_ lang: AppLanguage) {
        switch lang {
        case .system:
            UserDefaults.standard.removeObject(forKey: "AppleLanguages")
        case .english, .norwegian:
            UserDefaults.standard.set([lang.rawValue], forKey: "AppleLanguages")
        }
    }
}
