import Testing
import Foundation
@testable import Core

/// Sprint 6 — food-diary model logic: provenance (`source`), sodium / saturated-fat
/// scaling, daily totals, and the multi-source search contract (ADR-016 / ADR-018).
struct FoodModelsTests {

    // MARK: - FoodItem decoding (multi-source contract)

    @Test func foodItemDecodesSourceAndNewNutrients() throws {
        let json = """
        {
            "code": "mvt-1234",
            "name": "Storfe, ribeye, rå",
            "brand": null,
            "quantity": null,
            "source": "mvt",
            "energy_kcal_100g": 291,
            "carbs_100g": 0.0,
            "protein_100g": 20.8,
            "fat_100g": 23.0,
            "saturated_fat_100g": 9.5,
            "sodium_100g": 52
        }
        """.data(using: .utf8)!

        let item = try JSONDecoder.api.decode(FoodItem.self, from: json)
        #expect(item.source == .mvt)
        #expect(item.saturatedFat100g == 9.5)
        #expect(item.sodium100g == 52)
        #expect(item.source.supportsBarcode == false)
    }

    @Test func foodItemDefaultsSourceToOFFWhenMissing() throws {
        // Legacy payload without a `source` field still decodes (defaults to OFF).
        let json = """
        { "code": "737628064502", "name": "Branded snack", "energy_kcal_100g": 500 }
        """.data(using: .utf8)!

        let item = try JSONDecoder.api.decode(FoodItem.self, from: json)
        #expect(item.source == .off)
        #expect(item.source.supportsBarcode == true)
    }

    // MARK: - Scaling of the new nutrients

    @Test func foodItemScalesSodiumAndSaturatedFat() {
        let item = FoodItem(
            code: "x", name: "Cheese", source: .usda,
            saturatedFat100g: 18.0, sodium100g: 620
        )
        let grams = 40.0
        #expect(item.saturatedFatG(forGrams: grams) == 18.0 * 40 / 100)
        #expect(item.sodiumMg(forGrams: grams) == 620 * 40 / 100)
    }

    @Test func foodItemNeverInventsMissingNutrient() {
        let item = FoodItem(code: "x", name: "Sparse", source: .off)
        #expect(item.sodiumMg(forGrams: 100) == nil)
        #expect(item.saturatedFatG(forGrams: 100) == nil)
    }

    // MARK: - Payload provenance + barcode rules

    @Test func payloadFromWholeFoodSourceDropsBarcode() {
        // Whole-food sources have no barcodes — the payload must not carry the code.
        let item = FoodItem(code: "mvt-egg", name: "Egg", source: .mvt, energyKcal100g: 143)
        let payload = FoodEntryPayload(loggedOn: .now, meal: .breakfast, item: item, quantityG: 50)
        #expect(payload.barcode == nil)
        #expect(payload.source == .mvt)
        #expect(payload.energyKcal == 143 * 50 / 100)
    }

    @Test func payloadFromBrandedSourceKeepsBarcode() {
        let item = FoodItem(code: "7038010068980", name: "Yoghurt", source: .off, sodium100g: 50)
        let payload = FoodEntryPayload(loggedOn: .now, meal: .snack, item: item, quantityG: 200)
        #expect(payload.barcode == "7038010068980")
        #expect(payload.sodiumMg == 50 * 200 / 100)
    }

    // MARK: - Daily totals

    @Test func dailyTotalsSumPresentNutrientsOnly() {
        let entries = [
            FoodEntry(id: "1", loggedOn: .now, meal: .breakfast, foodName: "A",
                      energyKcal: 200, carbsG: 1, proteinG: 18, fatG: 14,
                      saturatedFatG: 4.5, sodiumMg: 210, source: .usda),
            FoodEntry(id: "2", loggedOn: .now, meal: .dinner, foodName: "B",
                      energyKcal: 300, carbsG: nil, proteinG: 25, fatG: 22,
                      saturatedFatG: nil, sodiumMg: 90, source: .mvt),
        ]
        let totals = DailyTotals.compute(from: entries)
        #expect(totals.energyKcal == 500)
        #expect(totals.proteinG == 43)
        #expect(totals.carbsG == 1)          // nil carb on entry 2 skipped, not zeroed wrongly
        #expect(totals.saturatedFatG == 4.5) // only entry 1 had a value
        #expect(totals.sodiumMg == 300)
    }

    // MARK: - Search source contract

    @Test func searchSourceQueryValues() {
        #expect(FoodSearchSource.mvt.queryValue == "mvt")
        #expect(FoodSearchSource.all.queryValue == "all")
        #expect(FoodSearchSource.off.supportsBarcode == true)
        #expect(FoodSearchSource.all.supportsBarcode == true)
        #expect(FoodSearchSource.mvt.supportsBarcode == false)
    }
}
