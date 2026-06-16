import Core
import Recipes
import Foundation
import Observation

/// One category's worth of recipes in the catalogue list. `id` is the category
/// name (unique per section), so `ForEach` can iterate sections without a tuple.
struct RecipeCatalogSection: Identifiable {
    let category: String
    let recipes: [Recipe]
    var id: String { category }
}

/// View model for the Recipes tab. Owns the category filter, the "only free"
/// toggle, and authoring-sheet presentation; delegates all persistence to
/// `RecipesRepository`. The catalogue is loaded once and filtered in memory so
/// tapping a category chip is instant (no round-trip).
@MainActor
@Observable
final class RecipesViewModel {

    // MARK: - Filters

    /// `nil` shows every category; otherwise only recipes in this category.
    var selectedCategory: String?
    /// Hide premium recipes (mirrors the "Only free recipes" switch).
    var onlyFree = false

    // MARK: - Authoring

    var isCreatePresented = false
    var isImportPresented = false

    // MARK: - Error surfacing

    var errorMessage: String?

    // MARK: - Dependencies

    let repo: RecipesRepository

    init(repo: RecipesRepository) {
        self.repo = repo
    }

    // MARK: - Passthrough

    var isLoading: Bool { repo.isLoading }
    var allRecipes: [Recipe] { repo.recipes }

    // MARK: - Load

    func load() async {
        await repo.load()
        surfaceError()
    }

    // MARK: - Derivation

    /// Distinct categories present in the catalogue, sorted, for the chip row.
    var categories: [String] {
        Array(Set(repo.recipes.map(\.category))).sorted()
    }

    /// Recipes after applying the active category + free filters, newest first
    /// (the repository already returns newest-first).
    var filteredRecipes: [Recipe] {
        repo.recipes.filter { recipe in
            (selectedCategory == nil || recipe.category == selectedCategory)
                && (!onlyFree || !recipe.isPremium)
        }
    }

    /// The filtered recipes grouped into per-category sections, with the categories
    /// in stable alphabetical order — matching the screenshot's section-per-category
    /// layout. A named `Identifiable` type (rather than a tuple) so `ForEach` can key
    /// on it directly.
    var sections: [RecipeCatalogSection] {
        let grouped = Dictionary(grouping: filteredRecipes, by: \.category)
        return grouped.keys.sorted().map { RecipeCatalogSection(category: $0, recipes: grouped[$0] ?? []) }
    }

    var isEmpty: Bool { filteredRecipes.isEmpty }

    func selectCategory(_ category: String?) {
        selectedCategory = category
    }

    func isSelected(_ category: String?) -> Bool {
        selectedCategory == category
    }

    // MARK: - Favourite

    func toggleFavorite(_ recipe: Recipe) async {
        do {
            try await repo.setFavorite(id: recipe.id, favorite: !recipe.isFavorite)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Authoring

    func createRecipe(_ payload: RecipePayload) async -> Bool {
        do {
            try await repo.create(payload)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func updateRecipe(id: String, _ payload: RecipePayload) async -> Bool {
        do {
            try await repo.update(id: id, payload)
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// The freshest copy of a recipe from the catalogue (favourite toggles and
    /// edits update it in place), falling back to `fallback` if it was removed.
    func current(_ fallback: Recipe) -> Recipe {
        repo.recipes.first { $0.id == fallback.id } ?? fallback
    }

    func deleteRecipe(_ recipe: Recipe) async {
        do {
            try await repo.delete(id: recipe.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Helpers

    private func surfaceError() {
        if let err = repo.error { errorMessage = err.localizedDescription }
    }
}
