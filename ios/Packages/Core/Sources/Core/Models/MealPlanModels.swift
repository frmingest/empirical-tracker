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
    public let note: String?
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
        note: String? = nil,
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
        self.note = note
        self.done = done
        self.planId = planId
    }

    // `done` may be absent on legacy payloads; default to `false`.
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id          = try c.decode(String.self, forKey: .id)
        scheduledOn = try c.decode(Date.self, forKey: .scheduledOn)
        meal        = try c.decode(Meal.self, forKey: .meal)
        foodName    = try c.decode(String.self, forKey: .foodName)
        brand       = try c.decodeIfPresent(String.self, forKey: .brand)
        barcode     = try c.decodeIfPresent(String.self, forKey: .barcode)
        quantityG   = try c.decodeIfPresent(Double.self, forKey: .quantityG)
        energyKcal  = try c.decodeIfPresent(Double.self, forKey: .energyKcal)
        carbsG      = try c.decodeIfPresent(Double.self, forKey: .carbsG)
        proteinG    = try c.decodeIfPresent(Double.self, forKey: .proteinG)
        fatG        = try c.decodeIfPresent(Double.self, forKey: .fatG)
        note        = try c.decodeIfPresent(String.self, forKey: .note)
        done        = try c.decodeIfPresent(Bool.self, forKey: .done) ?? false
        planId      = try c.decodeIfPresent(String.self, forKey: .planId)
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
            saturatedFatG: nil,
            sodiumMg: nil,
            source: nil,
            note: note
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
    public let note: String?
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
        self.scheduledOn = scheduledOn
        self.meal        = meal
        self.foodName    = item.name
        self.brand       = item.brand
        self.barcode     = item.source.supportsBarcode ? item.code : nil
        self.quantityG   = quantityG
        self.energyKcal  = item.energyKcal(forGrams: quantityG)
        self.carbsG      = item.carbsG(forGrams: quantityG)
        self.proteinG    = item.proteinG(forGrams: quantityG)
        self.fatG        = item.fatG(forGrams: quantityG)
        self.note        = note
        self.planId      = planId
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
        planId: String? = nil,
        note: String? = nil
    ) {
        self.scheduledOn = scheduledOn
        self.meal        = meal
        self.foodName    = foodName
        self.brand       = brand
        self.barcode     = nil
        self.quantityG   = quantityG
        self.energyKcal  = energyKcal
        self.carbsG      = carbsG
        self.proteinG    = proteinG
        self.fatG        = fatG
        self.note        = note
        self.planId      = planId
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
