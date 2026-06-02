import Testing
import Foundation
@testable import Core

/// Sprint 7 — meal-plan model logic: planned-meal decoding contract, the diary
/// promotion payload, per-100g scaling on scheduling, and the Monday-anchored
/// week grid (ADR-012).
struct MealPlanModelsTests {

    // MARK: - PlannedMeal decoding (calendar contract)

    @Test func plannedMealDecodesSnakeCaseAndDateAndDoneDefault() throws {
        let json = """
        {
            "id": "pm-1",
            "scheduled_on": "2026-06-03",
            "meal": "dinner",
            "food_name": "Storfe, ribeye, rå",
            "brand": null,
            "barcode": null,
            "quantity_g": 300,
            "energy_kcal": 873,
            "carbs_g": 0,
            "protein_g": 62.4,
            "fat_g": 69.0,
            "note": null,
            "plan_id": "mp-1"
        }
        """.data(using: .utf8)!

        let meal = try JSONDecoder.api.decode(PlannedMeal.self, from: json)
        #expect(meal.id == "pm-1")
        #expect(meal.meal == .dinner)
        #expect(meal.energyKcal == 873)
        #expect(meal.planId == "mp-1")
        // `done` absent → defaults to false, not a decode failure.
        #expect(meal.done == false)

        let comps = Calendar(identifier: .gregorian).dateComponents(
            in: TimeZone(identifier: "UTC")!, from: meal.scheduledOn
        )
        #expect(comps.year == 2026 && comps.month == 6 && comps.day == 3)
    }

    @Test func plannedMealDecodesDoneWhenPresent() throws {
        let json = """
        { "id": "x", "scheduled_on": "2026-06-03", "meal": "lunch",
          "food_name": "Eggs", "done": true }
        """.data(using: .utf8)!
        let meal = try JSONDecoder.api.decode(PlannedMeal.self, from: json)
        #expect(meal.done == true)
        #expect(meal.planId == nil)   // ungrouped meal decodes fine
    }

    // MARK: - Diary promotion

    @Test func diaryPayloadPreservesProvenanceAndAmounts() {
        let meal = PlannedMeal(
            id: "pm", scheduledOn: .now, meal: .snack,
            foodName: "Jarlsberg", brand: "TINE", barcode: "7038010009457",
            quantityG: 40, energyKcal: 137, carbsG: 0, proteinG: 10.8, fatG: 10.6
        )
        let payload = meal.diaryPayload()
        // Already-consumed totals copied straight across — no re-scaling.
        #expect(payload.energyKcal == 137)
        #expect(payload.quantityG == 40)
        // Barcode is preserved via the raw promotion initialiser (not dropped).
        #expect(payload.barcode == "7038010009457")
        #expect(payload.meal == .snack)
        #expect(payload.foodName == "Jarlsberg")
    }

    // MARK: - Scheduling payload (per-100g scaling, like the diary)

    @Test func plannedPayloadFromWholeFoodScalesAndDropsBarcode() {
        let item = FoodItem(code: "mvt-egg", name: "Egg", source: .mvt, energyKcal100g: 143)
        let payload = PlannedMealPayload(
            scheduledOn: .now, meal: .breakfast, item: item, quantityG: 50, planId: "mp-1"
        )
        #expect(payload.energyKcal == 143 * 50 / 100)
        #expect(payload.barcode == nil)        // whole-food sources carry no barcode
        #expect(payload.planId == "mp-1")
    }

    @Test func plannedPayloadFromBrandedKeepsBarcode() {
        let item = FoodItem(code: "7038010068980", name: "Yoghurt", source: .off, energyKcal100g: 60)
        let payload = PlannedMealPayload(scheduledOn: .now, meal: .snack, item: item, quantityG: 200)
        #expect(payload.barcode == "7038010068980")
        #expect(payload.energyKcal == 60 * 200 / 100)
    }

    @Test func freeTextPlannedPayloadHasNoMacrosByDefault() {
        let payload = PlannedMealPayload(
            scheduledOn: .now, meal: .lunch, foodName: "Ribeye + eggs"
        )
        #expect(payload.barcode == nil)
        #expect(payload.energyKcal == nil)   // free text never invents nutrition
        #expect(payload.foodName == "Ribeye + eggs")
    }

    // MARK: - Week grid (Monday-anchored, locale-independent)

    @Test func planWeekStartsOnMondayRegardlessOfLocale() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        cal.firstWeekday = 1 // Sunday — the week helper must ignore this.

        // 2026-06-03 is a Wednesday.
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 6, day: 3))!
        let week = PlanWeek(containing: wednesday, calendar: cal)

        #expect(week.days.count == 7)
        let startComps = cal.dateComponents([.year, .month, .day], from: week.start)
        #expect(startComps.month == 6 && startComps.day == 1)   // Monday 1 Jun
        let endComps = cal.dateComponents([.year, .month, .day], from: week.end)
        #expect(endComps.month == 6 && endComps.day == 7)       // Sunday 7 Jun
    }

    @Test func planWeekShiftMovesBySevenDays() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 6, day: 3))!
        let week = PlanWeek(containing: wednesday, calendar: cal)
        let next = week.shifted(by: 1, calendar: cal)
        let prev = week.shifted(by: -1, calendar: cal)

        let nextStart = cal.dateComponents([.month, .day], from: next.start)
        #expect(nextStart.month == 6 && nextStart.day == 8)    // following Monday
        let prevStart = cal.dateComponents([.month, .day], from: prev.start)
        #expect(prevStart.month == 5 && prevStart.day == 25)   // previous Monday
    }
}
