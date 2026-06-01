import Foundation

// MARK: - Meal

public enum Meal: String, Codable, CaseIterable, Identifiable, Sendable {
    case breakfast
    case lunch
    case dinner
    case snack
    case other

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .breakfast: return "Breakfast"
        case .lunch:     return "Lunch"
        case .dinner:    return "Dinner"
        case .snack:     return "Snack"
        case .other:     return "Other"
        }
    }

    public var icon: String {
        switch self {
        case .breakfast: return "sunrise"
        case .lunch:     return "sun.max"
        case .dinner:    return "moon"
        case .snack:     return "leaf"
        case .other:     return "ellipsis.circle"
        }
    }
}

// MARK: - FoodEntry

/// A logged food item in the diary. Mirrors `FoodEntry` in `web/src/lib/api.ts`.
public struct FoodEntry: Codable, Identifiable, Sendable {
    public let id: String
    public let loggedOn: Date
    public let meal: Meal
    public let foodName: String
    public let brand: String?
    public let barcode: String?
    public let quantityG: Double?
    /// Actual energy consumed (already scaled by quantity).
    public let energyKcal: Double?
    public let carbsG: Double?
    public let proteinG: Double?
    public let fatG: Double?
    public let note: String?
}

// MARK: - FoodItem (search result from Open Food Facts proxy)

public struct FoodItem: Codable, Identifiable, Sendable {
    public let code: String
    public let name: String
    public let brand: String?
    public let quantity: String?
    /// Nutrients expressed per 100 g — scale by (quantityG / 100) client-side.
    public let energyKcal100g: Double?
    public let carbs100g: Double?
    public let protein100g: Double?
    public let fat100g: Double?

    public var id: String { code }

    // MARK: Computed nutrients for a given serving

    public func energyKcal(forGrams g: Double) -> Double? {
        guard let base = energyKcal100g else { return nil }
        return base * g / 100
    }

    public func carbsG(forGrams g: Double) -> Double? {
        guard let base = carbs100g else { return nil }
        return base * g / 100
    }

    public func proteinG(forGrams g: Double) -> Double? {
        guard let base = protein100g else { return nil }
        return base * g / 100
    }

    public func fatG(forGrams g: Double) -> Double? {
        guard let base = fat100g else { return nil }
        return base * g / 100
    }
}

// MARK: - FoodEntryPayload (POST body)

public struct FoodEntryPayload: Encodable, Sendable {
    public let loggedOn: Date
    public let meal: Meal
    public let foodName: String
    public let brand: String?
    public let barcode: String?
    public let quantityG: Double?
    public let energyKcal: Double?
    public let carbsG: Double?
    public let proteinG: Double?
    public let fatG: Double?
    public let note: String?

    /// Convenience initialiser that pre-scales per-100g nutrients from a `FoodItem`.
    public init(
        loggedOn: Date,
        meal: Meal,
        item: FoodItem,
        quantityG: Double,
        note: String? = nil
    ) {
        self.loggedOn   = loggedOn
        self.meal       = meal
        self.foodName   = item.name
        self.brand      = item.brand
        self.barcode    = item.code
        self.quantityG  = quantityG
        self.energyKcal = item.energyKcal(forGrams: quantityG)
        self.carbsG     = item.carbsG(forGrams: quantityG)
        self.proteinG   = item.proteinG(forGrams: quantityG)
        self.fatG       = item.fatG(forGrams: quantityG)
        self.note       = note
    }

    /// Freetext-only entry (no OFF product).
    public init(
        loggedOn: Date,
        meal: Meal,
        foodName: String,
        brand: String? = nil,
        quantityG: Double? = nil,
        energyKcal: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        note: String? = nil
    ) {
        self.loggedOn   = loggedOn
        self.meal       = meal
        self.foodName   = foodName
        self.brand      = brand
        self.barcode    = nil
        self.quantityG  = quantityG
        self.energyKcal = energyKcal
        self.carbsG     = carbsG
        self.proteinG   = proteinG
        self.fatG       = fatG
        self.note       = note
    }
}

// MARK: - DailyTotals

/// Computed from a day's `FoodEntry` array.
public struct DailyTotals: Sendable {
    public let energyKcal: Double
    public let carbsG: Double
    public let proteinG: Double
    public let fatG: Double

    public static func compute(from entries: [FoodEntry]) -> DailyTotals {
        DailyTotals(
            energyKcal: entries.compactMap(\.energyKcal).reduce(0, +),
            carbsG:     entries.compactMap(\.carbsG).reduce(0, +),
            proteinG:   entries.compactMap(\.proteinG).reduce(0, +),
            fatG:       entries.compactMap(\.fatG).reduce(0, +)
        )
    }
}
