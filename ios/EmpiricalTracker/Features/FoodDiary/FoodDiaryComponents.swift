import Core
import SwiftUI

// MARK: - Meal localisation (view layer)

extension Meal {
    /// Localised section title. The Core `displayName` stays English-only for logging.
    var localizedName: String {
        switch self {
        case .breakfast: return String(localized: "food.meal.breakfast")
        case .lunch:     return String(localized: "food.meal.lunch")
        case .dinner:    return String(localized: "food.meal.dinner")
        case .snack:     return String(localized: "food.meal.snack")
        case .other:     return String(localized: "food.meal.other")
        }
    }
}

// MARK: - Source colour (view layer only — mirrors DietEvent.Kind.color)

extension FoodSource {
    var uiColor: Color {
        switch self {
        case .mvt:  return .inRange   // Norwegian lab-analysed whole foods
        case .usda: return .accent    // US lab-analysed whole foods
        case .off:  return .textMuted // crowd-sourced branded products
        }
    }
}

// MARK: - Source badge

/// Small capsule that tells the user where a food's numbers came from (ADR-018).
/// Uses text (not colour alone) so it stays legible for colour-blind users.
struct FoodSourceBadge: View {
    let source: FoodSource

    var body: some View {
        Text(source.badge)
            .font(.labelSmall)
            .foregroundStyle(source.uiColor)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(source.uiColor.opacity(0.12), in: Capsule())
            .accessibilityLabel(Text(source.displayName))
    }
}

// MARK: - Nutrition formatting

enum NutritionFormat {
    /// Energy as a whole number of kcal, e.g. "512 kcal". `nil` → em dash.
    static func energy(_ kcal: Double?) -> String {
        guard let kcal else { return "—" }
        return "\(Int(kcal.rounded())) \(String(localized: "food.unit.kcal"))"
    }

    /// Grams to one decimal, e.g. "12.4 g". `nil` → em dash.
    static func grams(_ g: Double?) -> String {
        guard let g else { return "—" }
        return "\(g.formatted(.number.precision(.fractionLength(0...1)))) \(String(localized: "food.unit.g"))"
    }

    /// Milligrams as a whole number, e.g. "640 mg". `nil` → em dash.
    static func milligrams(_ mg: Double?) -> String {
        guard let mg else { return "—" }
        return "\(Int(mg.rounded())) \(String(localized: "food.unit.mg"))"
    }

    /// Compact one-line macro summary with a single trailing unit, e.g. "C 8 · P 8 · F 17 g".
    /// Values round to whole grams so diary rows stay on a single, scannable line — the
    /// per-item detail keeps full precision. When every macro is missing the whole summary
    /// collapses to a single em dash rather than "C — · P — · F —".
    static func macroSummary(carbs: Double?, protein: Double?, fat: Double?) -> String {
        guard [carbs, protein, fat].contains(where: { $0 != nil }) else { return "—" }
        func whole(_ value: Double?) -> String {
            guard let value else { return "—" }
            return "\(Int(value.rounded()))"
        }
        let unit = String(localized: "food.unit.g")
        return "C \(whole(carbs)) · P \(whole(protein)) · F \(whole(fat)) \(unit)"
    }
}
