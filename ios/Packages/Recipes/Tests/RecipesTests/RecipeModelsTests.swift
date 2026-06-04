import XCTest
@testable import Recipes
import Core

final class RecipeModelsTests: XCTestCase {

    /// The catalogue payload decodes the derived `is_favorite` / `is_new` flags and
    /// the jsonb ingredient / instruction arrays using the shared snake_case decoder.
    func testDecodeRecipeFromBackendShape() throws {
        let json = """
        {
            "id": "r1",
            "title": "Pork Belly Breakfast Bites",
            "category": "Breakfast",
            "image_url": "https://example.com/pork.jpg",
            "serving_size": "1 serving",
            "calories_kcal": 612,
            "protein_g": 34,
            "fat_g": 52,
            "carbs_g": 0,
            "ingredients": ["8 oz pork belly", "1 tbsp butter", "Salt to taste"],
            "instructions": ["Pat dry", "Sear"],
            "fact": "Pork belly is energy-dense.",
            "is_public": true,
            "is_premium": false,
            "is_favorite": true,
            "is_new": true,
            "created_at": "2026-06-04T07:37:00.123456Z"
        }
        """.data(using: .utf8)!

        let recipe = try JSONDecoder.api.decode(Recipe.self, from: json)
        XCTAssertEqual(recipe.title, "Pork Belly Breakfast Bites")
        XCTAssertEqual(recipe.ingredients.count, 3)
        XCTAssertEqual(recipe.instructions, ["Pat dry", "Sear"])
        XCTAssertEqual(recipe.caloriesKcal, 612)
        XCTAssertTrue(recipe.isFavorite)
        XCTAssertTrue(recipe.isNew)
        XCTAssertNotNil(recipe.createdAt)
    }

    /// Missing optional flags / lists default rather than throwing.
    func testDecodeTolerantOfMissingFields() throws {
        let json = """
        { "id": "r2", "title": "Bare", "category": "Beef" }
        """.data(using: .utf8)!

        let recipe = try JSONDecoder.api.decode(Recipe.self, from: json)
        XCTAssertEqual(recipe.ingredients, [])
        XCTAssertEqual(recipe.instructions, [])
        XCTAssertFalse(recipe.isFavorite)
        XCTAssertFalse(recipe.isPremium)
    }

    func testTogglingFavoriteFlipsOnlyTheFlag() {
        let recipe = Recipe(id: "r1", title: "X", category: "Beef", isFavorite: false)
        let toggled = recipe.togglingFavorite()
        XCTAssertTrue(toggled.isFavorite)
        XCTAssertEqual(toggled.id, recipe.id)
        XCTAssertEqual(toggled.title, recipe.title)
    }

    /// The POST/PUT body serialises to the snake_case shape the API validates.
    func testPayloadEncodesSnakeCase() throws {
        let payload = RecipePayload(
            title: "Ribeye",
            category: "Beef",
            caloriesKcal: 700,
            ingredients: ["1 ribeye"],
            instructions: ["Sear it"],
            isPublic: true
        )
        let data = try JSONEncoder.api.encode(payload)
        let obj = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        XCTAssertEqual(obj["title"] as? String, "Ribeye")
        XCTAssertEqual(obj["calories_kcal"] as? Double, 700)
        XCTAssertEqual(obj["is_public"] as? Bool, true)
        XCTAssertEqual(obj["ingredients"] as? [String], ["1 ribeye"])
    }
}
