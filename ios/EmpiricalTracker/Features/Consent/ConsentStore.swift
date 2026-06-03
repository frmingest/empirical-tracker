import Foundation
import Observation

/// Records the user's explicit consent to processing their health data.
///
/// Empirical Tracker handles GDPR special-category (health) data — blood
/// biomarkers, body metrics, and diet logs — so a clear, affirmative consent
/// step is required before the main app is shown for the first time.
///
/// Consent is **versioned**: bumping ``currentVersion`` (e.g. when the privacy
/// policy materially changes) invalidates prior acceptance and re-presents the
/// consent screen. Acceptance is stored locally in `UserDefaults`; it gates the
/// UI but is not a substitute for the signup-time consent recorded server-side.
@MainActor
@Observable
public final class ConsentStore {

    /// Current consent revision. Bump when the health-data processing terms change.
    public static let currentVersion = 1

    /// True once the user has accepted the *current* consent version.
    public private(set) var hasConsented: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let accepted = defaults.integer(forKey: Keys.acceptedVersion)
        self.hasConsented = accepted >= ConsentStore.currentVersion
    }

    /// Records affirmative consent to the current version.
    public func accept() {
        defaults.set(ConsentStore.currentVersion, forKey: Keys.acceptedVersion)
        hasConsented = true
    }

    /// Clears stored consent. Called on sign-out so the next user must consent
    /// themselves rather than inheriting the previous user's acceptance.
    public func reset() {
        defaults.removeObject(forKey: Keys.acceptedVersion)
        hasConsented = false
    }

    private enum Keys {
        /// Highest consent version the user has accepted (0 = never).
        static let acceptedVersion = "consent.acceptedVersion"
    }
}
