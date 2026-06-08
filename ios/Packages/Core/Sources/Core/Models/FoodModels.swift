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

// MARK: - FoodSource (provenance)

/// Where a food's numbers came from. Stamped on every search result and stored on
/// each logged entry so the diary can show a provenance badge (ADR-018).
/// - `off`  Open Food Facts — branded / barcode products (crowd-sourced)
/// - `mvt`  Matvaretabellen — Norwegian whole foods (government, lab-analysed)
/// - `usda` USDA FoodData Central — American whole foods (government, lab-analysed)
public enum FoodSource: String, Codable, CaseIterable, Identifiable, Sendable {
    case off
    case mvt
    case usda
    /// User-contributed item from the custom_foods catalogue.
    case custom

    public var id: String { rawValue }

    /// Short badge text shown on rows. Mirrors the badges in `docs/NUTRITION_DATA.md`.
    public var badge: String {
        switch self {
        case .off:    return "OFF"
        case .mvt:    return "NO"
        case .usda:   return "US"
        case .custom: return "MY"
        }
    }

    /// Full attribution name.
    public var displayName: String {
        switch self {
        case .off:    return "Open Food Facts"
        case .mvt:    return "Matvaretabellen"
        case .usda:   return "USDA FoodData Central"
        case .custom: return "My Foods"
        }
    }

    /// Whether barcodes route to this source.
    public var supportsBarcode: Bool { self == .off || self == .custom }
}

// MARK: - FoodSearchSource (selector)

/// The source the user is searching against. Adds `all` (fan-out merge) on top of the
/// three provenance sources. Maps to `GET /food-diary/search?source=…` (ADR-018 §2).
/// Defaults to `all` — merging the lab-analysed whole-food tables with branded packs
/// so results are never blank. Narrowing to one source is a secondary, opt-in filter
/// (the UI surfaces it as a compact menu chip, not an always-visible segmented bar).
public enum FoodSearchSource: String, CaseIterable, Identifiable, Sendable {
    case mvt
    case usda
    case off
    case all

    public var id: String { rawValue }

    /// Value sent as the `source` query parameter.
    public var queryValue: String { rawValue }

    /// Whether the native barcode scanner is offered for this selection.
    /// Barcodes are Open Food Facts only, so they apply to `.off` and `.all`.
    public var supportsBarcode: Bool { self == .off || self == .all }
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
    /// Saturated fat consumed, in grams (ADR-016).
    public let saturatedFatG: Double?
    /// Sodium consumed, in milligrams (ADR-016).
    public let sodiumMg: Double?
    /// Provenance of the numbers (ADR-018). `nil` for legacy / free-text entries.
    public let source: FoodSource?
    public let note: String?
    /// Free-text ingredients snapshot copied from the source product at log time
    /// (product / custom sources). `nil` for free-text or whole-food entries.
    public let ingredients: String?

    public init(
        id: String,
        loggedOn: Date,
        meal: Meal,
        foodName: String,
        brand: String? = nil,
        barcode: String? = nil,
        quantityG: Double? = nil,
        energyKcal: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        saturatedFatG: Double? = nil,
        sodiumMg: Double? = nil,
        source: FoodSource? = nil,
        note: String? = nil,
        ingredients: String? = nil
    ) {
        self.id = id
        self.loggedOn = loggedOn
        self.meal = meal
        self.foodName = foodName
        self.brand = brand
        self.barcode = barcode
        self.quantityG = quantityG
        self.energyKcal = energyKcal
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fatG = fatG
        self.saturatedFatG = saturatedFatG
        self.sodiumMg = sodiumMg
        self.source = source
        self.note = note
        self.ingredients = ingredients
    }
}

// MARK: - FoodItem (search result from the multi-source food proxy)

public struct FoodItem: Codable, Identifiable, Sendable {
    public let code: String
    public let name: String
    public let brand: String?
    public let quantity: String?
    /// Provenance of these numbers (ADR-018). Defaults to `.off` for legacy payloads.
    public let source: FoodSource
    /// Nutrients expressed per 100 g — scale by (quantityG / 100) client-side.
    public let energyKcal100g: Double?
    public let carbs100g: Double?
    public let protein100g: Double?
    public let fat100g: Double?
    /// Saturated fat per 100 g, in grams (ADR-016).
    public let saturatedFat100g: Double?
    /// Sodium per 100 g, in milligrams (ADR-016).
    public let sodium100g: Double?
    /// Free-text ingredients list, when the source provides one (product / custom
    /// sources). `nil` for whole-food tables that have no ingredients.
    public let ingredients: String?

    public var id: String { code }

    public init(
        code: String,
        name: String,
        brand: String? = nil,
        quantity: String? = nil,
        source: FoodSource = .off,
        energyKcal100g: Double? = nil,
        carbs100g: Double? = nil,
        protein100g: Double? = nil,
        fat100g: Double? = nil,
        saturatedFat100g: Double? = nil,
        sodium100g: Double? = nil,
        ingredients: String? = nil
    ) {
        self.code = code
        self.name = name
        self.brand = brand
        self.quantity = quantity
        self.source = source
        self.energyKcal100g = energyKcal100g
        self.carbs100g = carbs100g
        self.protein100g = protein100g
        self.fat100g = fat100g
        self.saturatedFat100g = saturatedFat100g
        self.sodium100g = sodium100g
        self.ingredients = ingredients
    }

    // Decode defensively: `source` is always stamped by the backend today, but default
    // to `.off` so older cached payloads still decode.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code             = try c.decode(String.self, forKey: .code)
        name             = try c.decode(String.self, forKey: .name)
        brand            = try c.decodeIfPresent(String.self, forKey: .brand)
        quantity         = try c.decodeIfPresent(String.self, forKey: .quantity)
        source           = try c.decodeIfPresent(FoodSource.self, forKey: .source) ?? .off
        energyKcal100g   = try c.decodeIfPresent(Double.self, forKey: .energyKcal100g)
        carbs100g        = try c.decodeIfPresent(Double.self, forKey: .carbs100g)
        protein100g      = try c.decodeIfPresent(Double.self, forKey: .protein100g)
        fat100g          = try c.decodeIfPresent(Double.self, forKey: .fat100g)
        saturatedFat100g = try c.decodeIfPresent(Double.self, forKey: .saturatedFat100g)
        sodium100g       = try c.decodeIfPresent(Double.self, forKey: .sodium100g)
        ingredients      = try c.decodeIfPresent(String.self, forKey: .ingredients)
    }

    // MARK: Computed nutrients for a given serving

    public func energyKcal(forGrams g: Double) -> Double? { scale(energyKcal100g, g) }
    public func carbsG(forGrams g: Double) -> Double?     { scale(carbs100g, g) }
    public func proteinG(forGrams g: Double) -> Double?   { scale(protein100g, g) }
    public func fatG(forGrams g: Double) -> Double?       { scale(fat100g, g) }
    public func saturatedFatG(forGrams g: Double) -> Double? { scale(saturatedFat100g, g) }
    public func sodiumMg(forGrams g: Double) -> Double?      { scale(sodium100g, g) }

    /// Linear mass scaling only — never invents a value when the source omits one.
    private func scale(_ per100g: Double?, _ grams: Double) -> Double? {
        guard let per100g else { return nil }
        return per100g * grams / 100
    }
}

// MARK: - FoodEntryUpdatePayload (PUT /food-diary/{id})

public struct FoodEntryUpdatePayload: Encodable, Sendable {
    public let meal: Meal
    public let foodName: String
    public let brand: String?
    public let quantityG: Double?
    public let energyKcal: Double?
    public let carbsG: Double?
    public let proteinG: Double?
    public let fatG: Double?
    public let saturatedFatG: Double?
    public let sodiumMg: Double?
    public let note: String?

    public init(
        meal: Meal,
        foodName: String,
        brand: String? = nil,
        quantityG: Double? = nil,
        energyKcal: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        saturatedFatG: Double? = nil,
        sodiumMg: Double? = nil,
        note: String? = nil
    ) {
        self.meal          = meal
        self.foodName      = foodName
        self.brand         = brand
        self.quantityG     = quantityG
        self.energyKcal    = energyKcal
        self.carbsG        = carbsG
        self.proteinG      = proteinG
        self.fatG          = fatG
        self.saturatedFatG = saturatedFatG
        self.sodiumMg      = sodiumMg
        self.note          = note
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
    public let saturatedFatG: Double?
    public let sodiumMg: Double?
    public let source: FoodSource?
    public let note: String?
    /// Ingredients snapshot copied from the product at log time, so the diary entry
    /// keeps them independently of the source food (product / custom sources only).
    public let ingredients: String?

    /// Convenience initialiser that pre-scales per-100g nutrients from a `FoodItem`.
    public init(
        loggedOn: Date,
        meal: Meal,
        item: FoodItem,
        quantityG: Double,
        note: String? = nil
    ) {
        self.loggedOn      = loggedOn
        self.meal          = meal
        self.foodName      = item.name
        self.brand         = item.brand
        self.barcode       = (item.source.supportsBarcode && !item.code.isEmpty) ? item.code : nil
        self.quantityG     = quantityG
        self.energyKcal    = item.energyKcal(forGrams: quantityG)
        self.carbsG        = item.carbsG(forGrams: quantityG)
        self.proteinG      = item.proteinG(forGrams: quantityG)
        self.fatG          = item.fatG(forGrams: quantityG)
        self.saturatedFatG = item.saturatedFatG(forGrams: quantityG)
        self.sodiumMg      = item.sodiumMg(forGrams: quantityG)
        self.source        = item.source
        self.note          = note
        self.ingredients   = item.ingredients
    }

    /// Freetext-only entry (no product match).
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
        saturatedFatG: Double? = nil,
        sodiumMg: Double? = nil,
        note: String? = nil
    ) {
        self.loggedOn      = loggedOn
        self.meal          = meal
        self.foodName      = foodName
        self.brand         = brand
        self.barcode       = nil
        self.quantityG     = quantityG
        self.energyKcal    = energyKcal
        self.carbsG        = carbsG
        self.proteinG      = proteinG
        self.fatG          = fatG
        self.saturatedFatG = saturatedFatG
        self.sodiumMg      = sodiumMg
        self.source        = nil
        self.note          = note
        self.ingredients   = nil
    }

    /// Raw initialiser used when promoting an already-stored record (e.g. a planned
    /// meal — ADR-012) whose nutrient fields are already consumed-amount totals.
    /// Preserves `barcode` and `source` so the promoted diary entry keeps its
    /// provenance rather than degrading to a free-text row.
    public init(
        loggedOn: Date,
        meal: Meal,
        foodName: String,
        brand: String?,
        barcode: String?,
        quantityG: Double?,
        energyKcal: Double?,
        carbsG: Double?,
        proteinG: Double?,
        fatG: Double?,
        saturatedFatG: Double?,
        sodiumMg: Double?,
        source: FoodSource?,
        note: String?,
        ingredients: String? = nil
    ) {
        self.loggedOn      = loggedOn
        self.meal          = meal
        self.foodName      = foodName
        self.brand         = brand
        self.barcode       = barcode
        self.quantityG     = quantityG
        self.energyKcal    = energyKcal
        self.carbsG        = carbsG
        self.proteinG      = proteinG
        self.fatG          = fatG
        self.saturatedFatG = saturatedFatG
        self.sodiumMg      = sodiumMg
        self.source        = source
        self.note          = note
        self.ingredients   = ingredients
    }
}

// MARK: - DailyTotals

/// Computed from a day's `FoodEntry` array. Sums only the values that are present —
/// missing nutrients are skipped, never estimated (`docs/NUTRITION_DATA.md`).
public struct DailyTotals: Sendable {
    public let energyKcal: Double
    public let carbsG: Double
    public let proteinG: Double
    public let fatG: Double
    public let saturatedFatG: Double
    public let sodiumMg: Double

    public init(
        energyKcal: Double,
        carbsG: Double,
        proteinG: Double,
        fatG: Double,
        saturatedFatG: Double,
        sodiumMg: Double
    ) {
        self.energyKcal = energyKcal
        self.carbsG = carbsG
        self.proteinG = proteinG
        self.fatG = fatG
        self.saturatedFatG = saturatedFatG
        self.sodiumMg = sodiumMg
    }

    public static func compute(from entries: [FoodEntry]) -> DailyTotals {
        DailyTotals(
            energyKcal:    entries.compactMap(\.energyKcal).reduce(0, +),
            carbsG:        entries.compactMap(\.carbsG).reduce(0, +),
            proteinG:      entries.compactMap(\.proteinG).reduce(0, +),
            fatG:          entries.compactMap(\.fatG).reduce(0, +),
            saturatedFatG: entries.compactMap(\.saturatedFatG).reduce(0, +),
            sodiumMg:      entries.compactMap(\.sodiumMg).reduce(0, +)
        )
    }
}

// MARK: - ParsedLabel (response from POST /food-diary/parse-label)

/// Structured nutrients extracted from a nutrition-label OCR scan by Claude Haiku.
/// All nutrient fields are per 100 g. Nil means the value was not found — never invented.
public struct ParsedLabel: Decodable, Identifiable, Sendable {
    public let id = UUID()
    public let foodName: String?
    public let brand: String?
    public let energyKcal100g: Double?
    public let carbs100g: Double?
    public let protein100g: Double?
    public let fat100g: Double?
    public let saturatedFat100g: Double?
    public let sodiumMg100g: Double?
    public let servingG: Double?
    public let ingredients: String?
    public let ocrRaw: [String: AnyCodable]?

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        foodName          = try c.decodeIfPresent(String.self, forKey: .name) // backend key is "name"
        brand             = try c.decodeIfPresent(String.self, forKey: .brand)
        energyKcal100g    = try c.decodeIfPresent(Double.self, forKey: .energyKcal100g)
        carbs100g         = try c.decodeIfPresent(Double.self, forKey: .carbs100g)
        protein100g       = try c.decodeIfPresent(Double.self, forKey: .protein100g)
        fat100g           = try c.decodeIfPresent(Double.self, forKey: .fat100g)
        saturatedFat100g  = try c.decodeIfPresent(Double.self, forKey: .saturatedFat100g)
        sodiumMg100g      = try c.decodeIfPresent(Double.self, forKey: .sodiumMg100g)
        servingG          = try c.decodeIfPresent(Double.self, forKey: .servingG)
        ingredients       = try c.decodeIfPresent(String.self, forKey: .ingredients)
        ocrRaw            = nil
    }

    private enum CodingKeys: String, CodingKey {
        case name, brand
        // convertFromSnakeCase calls .capitalized on each component after splitting on "_".
        // "100g".capitalized = "100G" (ICU treats the letter after digits as a new word),
        // so "energy_kcal_100g" → "energyKcal100G" — note the capital G.
        case energyKcal100g   = "energyKcal100G"
        case carbs100g        = "carbs100G"
        case protein100g      = "protein100G"
        case fat100g          = "fat100G"
        case saturatedFat100g = "saturatedFat100G"
        case sodiumMg100g     = "sodiumMg100G"
        case servingG   // "serving_g" → "servingG" — plain letter, no digit prefix, works fine
        case ingredients
    }

    /// Convert to a FoodItem so it integrates with the existing logging flow.
    public func toFoodItem(name overrideName: String? = nil) -> FoodItem {
        FoodItem(
            code: "",
            name: overrideName ?? foodName ?? "",
            brand: brand,
            source: .custom,
            energyKcal100g: energyKcal100g,
            carbs100g: carbs100g,
            protein100g: protein100g,
            fat100g: fat100g,
            saturatedFat100g: saturatedFat100g,
            sodium100g: sodiumMg100g,
            ingredients: ingredients
        )
    }
}

// MARK: - CustomFoodPayload (POST/PUT /food-diary/custom)

public struct CustomFoodPayload: Encodable, Sendable {
    public let foodName: String
    public let brand: String?
    public let barcode: String?
    public let energyKcal: Double?
    public let carbsG: Double?
    public let proteinG: Double?
    public let fatG: Double?
    public let saturatedFatG: Double?
    public let sodiumMg: Double?
    public let servingG: Double?
    public let ingredients: String?
    public let ocrRaw: [String: String]?
    /// The user's explicit "share to the common catalogue" choice. Serialised as
    /// `is_public`. It both shares the item with other users and is the consent
    /// gate for anonymised retention after deletion (ADR-027). Defaults to private.
    public let isPublic: Bool

    public init(
        foodName: String,
        brand: String? = nil,
        barcode: String? = nil,
        energyKcal: Double? = nil,
        carbsG: Double? = nil,
        proteinG: Double? = nil,
        fatG: Double? = nil,
        saturatedFatG: Double? = nil,
        sodiumMg: Double? = nil,
        servingG: Double? = nil,
        ingredients: String? = nil,
        ocrRaw: [String: String]? = nil,
        isPublic: Bool = false
    ) {
        self.foodName     = foodName
        self.brand        = brand
        self.barcode      = barcode
        self.energyKcal   = energyKcal
        self.carbsG       = carbsG
        self.proteinG     = proteinG
        self.fatG         = fatG
        self.saturatedFatG = saturatedFatG
        self.sodiumMg     = sodiumMg
        self.servingG     = servingG
        self.ingredients  = ingredients
        self.ocrRaw       = ocrRaw
        self.isPublic     = isPublic
    }
}

// MARK: - CustomFoodRecord (response from custom food CRUD)

public struct CustomFoodRecord: Decodable, Identifiable, Sendable {
    public let id: String
    public let foodName: String
    public let brand: String?
    public let barcode: String?
    public let energyKcal: Double?
    public let carbsG: Double?
    public let proteinG: Double?
    public let fatG: Double?
    public let saturatedFatG: Double?
    public let sodiumMg: Double?
    public let servingG: Double?
    public let ingredients: String?
    public let createdAt: Date?

    public func toFoodItem() -> FoodItem {
        FoodItem(
            code: id,
            name: foodName,
            brand: brand,
            source: .custom,
            energyKcal100g: energyKcal,
            carbs100g: carbsG,
            protein100g: proteinG,
            fat100g: fatG,
            saturatedFat100g: saturatedFatG,
            sodium100g: sodiumMg,
            ingredients: ingredients
        )
    }
}

// MARK: - AnyCodable shim (minimal — only used in ParsedLabel.ocrRaw)

public struct AnyCodable: Codable, Sendable {
    public let value: Any

    public init(_ value: Any) { self.value = value }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self)  { value = s; return }
        if let d = try? c.decode(Double.self)  { value = d; return }
        if let b = try? c.decode(Bool.self)    { value = b; return }
        value = NSNull()
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch value {
        case let s as String: try c.encode(s)
        case let d as Double: try c.encode(d)
        case let b as Bool:   try c.encode(b)
        default:              try c.encodeNil()
        }
    }
}
