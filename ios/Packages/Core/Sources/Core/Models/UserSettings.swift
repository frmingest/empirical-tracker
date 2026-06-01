import Foundation

/// User-specific dashboard preferences. Mirrors `UserSettings` in `web/src/lib/api.ts`.
public struct UserSettings: Codable, Sendable {
    /// Active diet focus filter.
    public var diet: DietFocus
    /// Biomarker `name_no` values shown when `diet == .custom`.
    public var customMarkers: [String]

    public init(diet: DietFocus = .all, customMarkers: [String] = []) {
        self.diet = diet
        self.customMarkers = customMarkers
    }

    public static let `default` = UserSettings()
}
