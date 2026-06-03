import Testing
import Foundation
@testable import Core

/// Validates that the `Codable` DTOs round-trip correctly against the shapes
/// returned by the live backend. These are the "contract snapshot" tests
/// referenced in Sprint 0 acceptance criteria.
///
/// Update the fixture JSON strings whenever the backend schema changes.
struct DTOContractTests {

    // MARK: - BiomarkerWithSeries

    @Test func biomarkerWithSeriesDecodes() throws {
        let json = """
        {
            "biomarker": {
                "id": "abc-123",
                "name_no": "LDL-kolesterol",
                "name_en": "LDL cholesterol",
                "unit": "mmol/L",
                "ref_range_raw": "< 3,0",
                "ref_low": null,
                "ref_high": 3.0,
                "ref_type": "lt"
            },
            "series": [
                { "tested_at": "2024-01-15", "value": 2.8, "in_range": true },
                { "tested_at": "2024-06-20", "value": 3.4, "in_range": false }
            ]
        }
        """.data(using: .utf8)!

        let result = try JSONDecoder.api.decode(BiomarkerWithSeries.self, from: json)
        #expect(result.biomarker.id == "abc-123")
        #expect(result.biomarker.nameNo == "LDL-kolesterol")
        #expect(result.biomarker.refType == .lt)
        #expect(result.series.count == 2)
        #expect(result.series[1].inRange == false)
        #expect(result.latestResult?.value == 3.4)
        #expect(result.trend == .rising)
    }

    // MARK: - ManualResultPayload (POST /biomarkers/results/manual)

    /// The backend keys manual results on `biomarker_id` (not `name_no`) and
    /// expects `tested_at` as a calendar date. See ADR-007.
    @Test func manualResultPayloadEncodesBiomarkerId() throws {
        var components = DateComponents()
        components.year = 2026
        components.month = 6
        components.day = 2
        let testedAt = Calendar(identifier: .gregorian).date(from: components)!

        let payload = ManualResultPayload(biomarkerId: "abc-123", value: 5.4, testedAt: testedAt)
        let data = try JSONEncoder.api.encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])

        #expect(object["biomarker_id"] as? String == "abc-123")
        #expect(object["value"] as? Double == 5.4)
        #expect(object["tested_at"] as? String == "2026-06-02")
        #expect(object["name_no"] == nil)
    }

    // MARK: - DietEvent

    @Test func dietEventDecodes() throws {
        let json = """
        {
            "id": "evt-1",
            "label": "Started carnivore",
            "kind": "diet",
            "started_on": "2024-03-01",
            "ended_on": null,
            "note": "Strict beef + salt"
        }
        """.data(using: .utf8)!

        let event = try JSONDecoder.api.decode(DietEvent.self, from: json)
        #expect(event.label == "Started carnivore")
        #expect(event.kind == .diet)
        #expect(event.isPeriod == false)
    }

    // MARK: - FoodEntry

    @Test func foodEntryDecodes() throws {
        let json = """
        {
            "id": "fe-1",
            "logged_on": "2024-06-01",
            "meal": "breakfast",
            "food_name": "Egg",
            "brand": null,
            "barcode": null,
            "quantity_g": 60.0,
            "energy_kcal": 93.0,
            "carbs_g": 0.4,
            "protein_g": 7.8,
            "fat_g": 6.3,
            "note": null
        }
        """.data(using: .utf8)!

        let entry = try JSONDecoder.api.decode(FoodEntry.self, from: json)
        #expect(entry.meal == .breakfast)
        #expect(entry.energyKcal == 93.0)
    }

    // MARK: - UserSettings

    @Test func userSettingsDecodes() throws {
        let json = """
        { "diet": "carnivore", "custom_markers": [] }
        """.data(using: .utf8)!

        let settings = try JSONDecoder.api.decode(UserSettings.self, from: json)
        #expect(settings.diet == .carnivore)
        #expect(settings.customMarkers.isEmpty)
    }

    // MARK: - FoodItem scaling

    @Test func foodItemNutrientScaling() {
        let item = FoodItem(
            code: "1234567890",
            name: "Smør",
            brand: "TINE",
            quantity: "500g",
            energyKcal100g: 744,
            carbs100g: 0.5,
            protein100g: 0.6,
            fat100g: 81.0
        )
        let grams = 15.0 // one tablespoon
        #expect(item.energyKcal(forGrams: grams) == 744 * 15 / 100)
        #expect(item.fatG(forGrams: grams) == 81.0 * 15 / 100)
    }

    // MARK: - MealPlan (Sprint 7 / ADR-012)

    @Test func mealPlanDecodes() throws {
        let json = """
        { "id": "mp-1", "name": "Carnivore week", "description": "Beef, eggs, butter." }
        """.data(using: .utf8)!

        let plan = try JSONDecoder.api.decode(MealPlan.self, from: json)
        #expect(plan.id == "mp-1")
        #expect(plan.name == "Carnivore week")
        #expect(plan.description == "Beef, eggs, butter.")
    }

    // MARK: - PlannedMeal (calendar)

    @Test func plannedMealDecodes() throws {
        let json = """
        {
            "id": "pm-1",
            "scheduled_on": "2024-06-03",
            "meal": "dinner",
            "food_name": "Ribeye",
            "brand": null,
            "barcode": null,
            "quantity_g": 300.0,
            "energy_kcal": 873.0,
            "carbs_g": 0.0,
            "protein_g": 62.4,
            "fat_g": 69.0,
            "note": null,
            "done": false,
            "plan_id": "mp-1"
        }
        """.data(using: .utf8)!

        let meal = try JSONDecoder.api.decode(PlannedMeal.self, from: json)
        #expect(meal.meal == .dinner)
        #expect(meal.energyKcal == 873.0)
        #expect(meal.done == false)
        #expect(meal.planId == "mp-1")
    }
}
