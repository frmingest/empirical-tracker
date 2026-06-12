import Foundation
import Observation

/// Optional daily intake targets the diary totals are read against (WISHLIST #6):
/// an energy target, a protein target (settable as g/kg of body weight now that
/// weight is tracked — ADR-017), and a carbohydrate ceiling for low-carb regimens.
///
/// Targets are the user's own numbers — the app never derives or recommends one
/// (decision-support posture). `UserDefaults`-backed and device-local; there is no
/// backend table yet (syncing targets across devices is a noted follow-up).
@MainActor
@Observable
public final class NutritionTargetsStore {

    // MARK: - State (nil = no target set)

    public var energyKcal: Double? {
        didSet { Self.write(energyKcal, key: Keys.energy) }
    }

    public var proteinG: Double? {
        didSet { Self.write(proteinG, key: Keys.protein) }
    }

    /// A ceiling, not a goal — drawn as "stay under" in the totals card.
    public var carbsMaxG: Double? {
        didSet { Self.write(carbsMaxG, key: Keys.carbsMax) }
    }

    public var hasAnyTarget: Bool {
        energyKcal != nil || proteinG != nil || carbsMaxG != nil
    }

    // MARK: - Init

    public init() {
        energyKcal = UserDefaults.standard.object(forKey: Keys.energy) as? Double
        proteinG   = UserDefaults.standard.object(forKey: Keys.protein) as? Double
        carbsMaxG  = UserDefaults.standard.object(forKey: Keys.carbsMax) as? Double
    }

    // MARK: - Private

    private static func write(_ value: Double?, key: String) {
        if let value {
            UserDefaults.standard.set(value, forKey: key)
        } else {
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    private enum Keys {
        static let energy   = "food.targets.energyKcal"
        static let protein  = "food.targets.proteinG"
        static let carbsMax = "food.targets.carbsMaxG"
    }
}
