import Foundation

// MARK: - MealPlan (named grouping)

/// A named, reusable meal plan ("Carnivore week", "Low-carb reset"). A label and
/// grouping only — it owns no meals directly; planned meals reference it by `planId`.
/// Mirrors `meal_plans` (ADR-012) and `MealPlan` in `web/src/lib/api.ts`.
public struct MealPlan: Codable, Identifiable, Sendable {
    public let id: String
    public let name: String
    public let description: String?

    public init(id: String, name: String, description: String? = nil) {
        self.id = id
        self.name = name
        self.description = description
    }
}

// MARK: - MealPlanPayload (POST body)

public struct MealPlanPayload: Encodable, Sendable {
    public let name: String
    public let description: String?

    public init(name: String, description: String? = nil) {
        self.name = name
        self.description = description
    }
}

// MARK: - PlannedMeal (a scheduled meal on the calendar)

/// One meal scheduled for a date. Nutrient fields are **consumed-amount totals**
/// (already scaled by `quantityG`), matching the food-diary durability rule
/// (ADR-011 / ADR-012). `planId` is nullable: deleting a plan keeps the meal,
/// un-grouped (`ON DELETE SET NULL`).
public struct PlannedMeal: Codable, Identifiable, Sendable {
    public let id: String
    public let scheduledOn: Date
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
    /// Ingredients snapshot copied from the product at schedule time, forwarded onto
    /// the diary entry when the meal is logged (product / custom sources only).
    public let ingredients: String?
    /// Cooked / eaten flag. Advisory only — it does not by itself create a diary
    /// entry; "Log to diary" is the explicit, auditable step (ADR-012).
    public let done: Bool
    /// Optional grouping plan. `nil` once its plan is deleted, or if scheduled ad-hoc.
    public let planId: String?

    public init(
        id: String,
        scheduledOn: Date,
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
        ingredients: String? = nil,
        done: Bool = false,
        planId: String? = nil
    ) {
        self.id = id
        self.scheduledOn = scheduledOn
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
        self.done = done
        self.planId = planId
    }

    // `done` may be absent on legacy payloads; default to `false`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id            = try c.decode(String.self, forKey: .id)
        // `scheduled_on` is a calendar date (`yyyy-MM-dd`). Parse it in the *current*
        // time zone so it lands on local midnight — matching the local week days the
        // Plan tab compares against in `MealPlanViewModel.meals(on:)`. Decoding it as
        // a UTC instant would shift the meal onto the wrong day for any non-UTC user.
        let scheduledRaw = try c.decode(String.self, forKey: .scheduledOn)
        guard let scheduled = CalendarDate.date(from: scheduledRaw) else {
            throw DecodingError.dataCorruptedError(
                forKey: .scheduledOn, in: c,
                debugDescription: "Expected a yyyy-MM-dd date, got \"\(scheduledRaw)\""
            )
        }
        scheduledOn   = scheduled
        meal          = try c.decode(Meal.self, forKey: .meal)
        foodName      = try c.decode(String.self, forKey: .foodName)
        brand         = try c.decodeIfPresent(String.self, forKey: .brand)
        barcode       = try c.decodeIfPresent(String.self, forKey: .barcode)
        quantityG     = try c.decodeIfPresent(Double.self, forKey: .quantityG)
        energyKcal    = try c.decodeIfPresent(Double.self, forKey: .energyKcal)
        carbsG        = try c.decodeIfPresent(Double.self, forKey: .carbsG)
        proteinG      = try c.decodeIfPresent(Double.self, forKey: .proteinG)
        fatG          = try c.decodeIfPresent(Double.self, forKey: .fatG)
        saturatedFatG = try c.decodeIfPresent(Double.self, forKey: .saturatedFatG)
        sodiumMg      = try c.decodeIfPresent(Double.self, forKey: .sodiumMg)
        source        = try c.decodeIfPresent(FoodSource.self, forKey: .source)
        note          = try c.decodeIfPresent(String.self, forKey: .note)
        ingredients   = try c.decodeIfPresent(String.self, forKey: .ingredients)
        done          = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        planId        = try c.decodeIfPresent(String.self, forKey: .planId)
    }

    /// Builds the diary payload for the "Log to diary" promotion (ADR-012). Reuses
    /// the already-consumed nutrient totals so no re-scaling or re-search is needed.
    public func diaryPayload(loggedOn: Date? = nil) -> FoodEntryPayload {
        FoodEntryPayload(
            loggedOn: loggedOn ?? scheduledOn,
            meal: meal,
            foodName: foodName,
            brand: brand,
            barcode: barcode,
            quantityG: quantityG,
            energyKcal: energyKcal,
            carbsG: carbsG,
            proteinG: proteinG,
            fatG: fatG,
            saturatedFatG: saturatedFatG,
            sodiumMg: sodiumMg,
            source: source,
            note: note,
            ingredients: ingredients
        )
    }
}

// MARK: - PlannedMealPayload (POST body)

public struct PlannedMealPayload: Encodable, Sendable {
    public let scheduledOn: Date
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
    public let ingredients: String?
    public let planId: String?

    /// Convenience initialiser that pre-scales per-100g nutrients from a `FoodItem`,
    /// mirroring `FoodEntryPayload.init(item:…)` so the planned meal stores
    /// consumed-amount totals.
    public init(
        scheduledOn: Date,
        meal: Meal,
        item: FoodItem,
        quantityG: Double,
        planId: String? = nil,
        note: String? = nil
    ) {
        self.scheduledOn  = scheduledOn
        self.meal         = meal
        self.foodName     = item.name
        self.brand        = item.brand
        self.barcode      = item.source.supportsBarcode ? item.code : nil
        self.quantityG    = quantityG
        self.energyKcal   = item.energyKcal(forGrams: quantityG)
        self.carbsG       = item.carbsG(forGrams: quantityG)
        self.proteinG     = item.proteinG(forGrams: quantityG)
        self.fatG         = item.fatG(forGrams: quantityG)
        self.saturatedFatG = item.saturatedFatG(forGrams: quantityG)
        self.sodiumMg     = item.sodiumMg(forGrams: quantityG)
        self.source       = item.source
        self.note         = note
        self.ingredients  = item.ingredients
        self.planId       = planId
    }

    /// Free-text planned meal (no product match) — e.g. "Ribeye + eggs".
    public init(
        scheduledOn: Date,
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
        source: FoodSource? = nil,
        planId: String? = nil,
        note: String? = nil
    ) {
        self.scheduledOn  = scheduledOn
        self.meal         = meal
        self.foodName     = foodName
        self.brand        = brand
        self.barcode      = nil
        self.quantityG    = quantityG
        self.energyKcal   = energyKcal
        self.carbsG       = carbsG
        self.proteinG     = proteinG
        self.fatG         = fatG
        self.saturatedFatG = saturatedFatG
        self.sodiumMg     = sodiumMg
        self.source       = source
        self.note         = note
        self.ingredients  = nil
        self.planId       = planId
    }

    /// Reschedules an existing planned meal onto a new day/slot, preserving its
    /// stored nutrition totals, provenance (barcode / source / ingredients) and
    /// plan grouping. Used by the client-side "Move": the calendar PATCH only
    /// updates `done`, so a move is recreate-then-delete (ADR-012).
    public init(rescheduling meal: PlannedMeal, toDate date: Date, slot: Meal) {
        self.scheduledOn   = date
        self.meal          = slot
        self.foodName      = meal.foodName
        self.brand         = meal.brand
        self.barcode       = meal.barcode
        self.quantityG     = meal.quantityG
        self.energyKcal    = meal.energyKcal
        self.carbsG        = meal.carbsG
        self.proteinG      = meal.proteinG
        self.fatG          = meal.fatG
        self.saturatedFatG = meal.saturatedFatG
        self.sodiumMg      = meal.sodiumMg
        self.source        = meal.source
        self.note          = meal.note
        self.ingredients   = meal.ingredients
        self.planId        = meal.planId
    }

    enum CodingKeys: String, CodingKey {
        case scheduledOn, meal, foodName, brand, barcode, quantityG, energyKcal
        case carbsG, proteinG, fatG, saturatedFatG, sodiumMg, source, note, ingredients, planId
    }

    /// `scheduled_on` is encoded as a calendar date (`yyyy-MM-dd`) rather than a full
    /// ISO-8601 timestamp. The picker hands us a midnight-*local* `Date`; serialising
    /// that as the shared encoder's UTC instant (e.g. `2026-06-03` 00:00 CEST →
    /// `2026-06-02T22:00:00Z`) truncates to the *previous* day server-side, so the
    /// meal never shows up on the day the user tapped. Mirrors `ManualResultPayload`
    /// (ADR-007). The remaining keys are converted to snake_case by `JSONEncoder.api`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(CalendarDate.string(from: scheduledOn), forKey: .scheduledOn)
        try c.encode(meal, forKey: .meal)
        try c.encode(foodName, forKey: .foodName)
        try c.encodeIfPresent(brand, forKey: .brand)
        try c.encodeIfPresent(barcode, forKey: .barcode)
        try c.encodeIfPresent(quantityG, forKey: .quantityG)
        try c.encodeIfPresent(energyKcal, forKey: .energyKcal)
        try c.encodeIfPresent(carbsG, forKey: .carbsG)
        try c.encodeIfPresent(proteinG, forKey: .proteinG)
        try c.encodeIfPresent(fatG, forKey: .fatG)
        try c.encodeIfPresent(saturatedFatG, forKey: .saturatedFatG)
        try c.encodeIfPresent(sodiumMg, forKey: .sodiumMg)
        try c.encodeIfPresent(source, forKey: .source)
        try c.encodeIfPresent(note, forKey: .note)
        try c.encodeIfPresent(ingredients, forKey: .ingredients)
        try c.encodeIfPresent(planId, forKey: .planId)
    }
}

// MARK: - PlannedMealDonePayload (PATCH body)

public struct PlannedMealDonePayload: Encodable, Sendable {
    public let done: Bool
    public init(done: Bool) { self.done = done }
}

// MARK: - PlanWeek (calendar grid helper)

/// A Monday→Sunday week, computed independently of `Calendar.firstWeekday` so the
/// grid matches the web client's fixed Monday-start week regardless of device locale
/// (ADR-012). Provides the inclusive [start, end] window the calendar endpoint fetches.
public struct PlanWeek: Equatable, Sendable {
    /// Midnight on the Monday that opens the week.
    public let start: Date
    /// The seven days Monday…Sunday.
    public let days: [Date]

    /// Midnight on the Sunday that closes the week (the last element of `days`).
    public var end: Date { days.last ?? start }

    /// The week containing `date` (defaults to today).
    public init(containing date: Date = .now, calendar: Calendar = .current) {
        var cal = calendar
        cal.firstWeekday = 2 // Monday, matching the web week boundary.
        let startOfDay = cal.startOfDay(for: date)
        // weekday: 1 = Sunday … 7 = Saturday. Distance back to Monday.
        let weekday = cal.component(.weekday, from: startOfDay)
        let daysFromMonday = (weekday + 5) % 7 // Mon→0, Tue→1 … Sun→6
        let monday = cal.date(byAdding: .day, value: -daysFromMonday, to: startOfDay) ?? startOfDay
        self.start = monday
        self.days = (0..<7).compactMap { cal.date(byAdding: .day, value: $0, to: monday) }
    }

    private init(start: Date, days: [Date]) {
        self.start = start
        self.days = days
    }

    /// The week `offset` weeks away (negative = earlier, positive = later).
    public func shifted(by offset: Int, calendar: Calendar = .current) -> PlanWeek {
        let anchor = calendar.date(byAdding: .day, value: offset * 7, to: start) ?? start
        return PlanWeek(containing: anchor, calendar: calendar)
    }
}
