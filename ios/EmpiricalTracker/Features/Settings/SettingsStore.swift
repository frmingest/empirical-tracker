import SwiftUI
import Observation

/// Persists user preferences (theme + language + units) via `UserDefaults`.
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

    /// Preferred unit system for entering / reading body measurements. Set during
    /// first-run profile setup and editable later in Settings. Storage stays metric;
    /// this is a presentation preference (see `MeasurementSystem`).
    public var measurementSystem: MeasurementSystem {
        didSet { UserDefaults.standard.set(measurementSystem.rawValue, forKey: Keys.units) }
    }

    // MARK: - Init

    public init() {
        let savedTheme    = UserDefaults.standard.string(forKey: Keys.theme)
        let savedLanguage = UserDefaults.standard.string(forKey: Keys.language)
        let savedUnits    = UserDefaults.standard.string(forKey: Keys.units)
        theme    = AppTheme(rawValue: savedTheme ?? "")       ?? .system
        language = AppLanguage(rawValue: savedLanguage ?? "") ?? .system
        measurementSystem = MeasurementSystem(rawValue: savedUnits ?? "") ?? .default
    }

    // MARK: - Private

    private enum Keys {
        static let theme    = "app.theme"
        static let language = "app.language"
        static let units    = "app.units"
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
