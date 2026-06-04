import Foundation
import Observation

/// Optional biological sex captured at onboarding. Biomarker reference ranges and
/// future intake targets (e.g. protein g/kg) differ by sex, so it is offered — but
/// always optional and including a "prefer not to say" option.
public enum BiologicalSex: String, CaseIterable, Sendable, Identifiable {
    case female
    case male
    case other
    case preferNotToSay

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .female:         return String(localized: "profile.sex.female")
        case .male:           return String(localized: "profile.sex.male")
        case .other:          return String(localized: "profile.sex.other")
        case .preferNotToSay: return String(localized: "profile.sex.prefer_not")
        }
    }
}

/// Stores the user's relatively static profile attributes — **height** and
/// **biological sex** — plus the flag that records whether the first-run profile
/// setup screen has been completed (or skipped).
///
/// These attributes have no `body_metrics` backend column (height rarely changes;
/// it is not a time-series) and there is no `user_profile` table yet, so — like
/// `ConsentStore` and `SettingsStore` — they are persisted locally in
/// `UserDefaults`. Time-series measurements entered during onboarding (weight,
/// waist) are written to the `body_metrics` backend instead.
///
/// The store is **reset on sign-out** so a different account on the same device is
/// offered its own setup rather than inheriting the previous user's height.
@MainActor
@Observable
public final class UserProfileStore {

    /// Canonical height in centimetres, `nil` until the user provides one.
    public private(set) var heightCm: Double?

    /// Optional biological sex, `nil` if not provided / "prefer not to say".
    public private(set) var biologicalSex: BiologicalSex?

    /// True once the user has finished (or skipped) the first-run profile setup.
    /// Gates `ProfileSetupView` in `RootView`.
    public private(set) var hasCompletedSetup: Bool

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let storedHeight = defaults.double(forKey: Keys.heightCm)
        self.heightCm = storedHeight > 0 ? storedHeight : nil
        self.biologicalSex = defaults.string(forKey: Keys.biologicalSex)
            .flatMap(BiologicalSex.init(rawValue:))
        self.hasCompletedSetup = defaults.bool(forKey: Keys.completedSetup)
    }

    /// Persists the static profile fields. Passing `nil` clears a field.
    public func update(heightCm: Double?, biologicalSex: BiologicalSex?) {
        self.heightCm = heightCm
        if let heightCm, heightCm > 0 {
            defaults.set(heightCm, forKey: Keys.heightCm)
        } else {
            defaults.removeObject(forKey: Keys.heightCm)
        }

        self.biologicalSex = biologicalSex
        if let biologicalSex {
            defaults.set(biologicalSex.rawValue, forKey: Keys.biologicalSex)
        } else {
            defaults.removeObject(forKey: Keys.biologicalSex)
        }
    }

    /// Marks the first-run setup as done (whether saved or skipped) so it is not
    /// shown again on this device for this user.
    public func markSetupComplete() {
        hasCompletedSetup = true
        defaults.set(true, forKey: Keys.completedSetup)
    }

    /// Clears all profile state. Called on sign-out so the next user starts clean.
    public func reset() {
        heightCm = nil
        biologicalSex = nil
        hasCompletedSetup = false
        defaults.removeObject(forKey: Keys.heightCm)
        defaults.removeObject(forKey: Keys.biologicalSex)
        defaults.removeObject(forKey: Keys.completedSetup)
    }

    private enum Keys {
        static let heightCm = "profile.heightCm"
        static let biologicalSex = "profile.biologicalSex"
        static let completedSetup = "profile.completedSetup"
    }
}
