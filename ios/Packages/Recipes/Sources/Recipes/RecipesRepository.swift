import Core
import Foundation
import Observation

/// Recipe catalogue + authoring CRUD, plus the per-user favourite star. Mirrors
/// every route under `/recipes` in `api/app/recipes/router.py`.
///
/// The repository owns the canonical recipe list; view models read from it. Writes
/// (create / update / delete / favourite) update the in-memory list optimistically
/// so the catalogue and detail screens stay consistent without a full reload.
@MainActor
@Observable
public final class RecipesRepository {

    // MARK: - State

    /// All recipes visible to the user (their own + the public catalogue),
    /// newest first — as returned by the last `load`.
    public var recipes: [Recipe] = []

    public var isLoading = false
    public var error: APIError?

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Reads

    /// Loads the catalogue, optionally narrowed to a category and/or free recipes.
    public func load(category: String? = nil, onlyFree: Bool = false) async {
        isLoading = true
        error = nil
        do {
            var query: [URLQueryItem] = []
            if let category { query.append(URLQueryItem(name: "category", value: category)) }
            if onlyFree { query.append(URLQueryItem(name: "only_free", value: "true")) }
            recipes = try await client.request(.get("/recipes", query: query.isEmpty ? nil : query))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
        isLoading = false
    }

    /// Fetches a single recipe by id (used to refresh the detail screen).
    public func fetch(id: String) async throws -> Recipe {
        try await client.request(.get("/recipes/\(id)"))
    }

    // MARK: - Authoring

    @discardableResult
    public func create(_ payload: RecipePayload) async throws -> Recipe {
        let created: Recipe = try await client.request(.post("/recipes", body: payload))
        recipes.insert(created, at: 0)
        return created
    }

    @discardableResult
    public func update(id: String, _ payload: RecipePayload) async throws -> Recipe {
        let updated: Recipe = try await client.request(.put("/recipes/\(id)", body: payload))
        if let idx = recipes.firstIndex(where: { $0.id == id }) {
            recipes[idx] = updated
        }
        return updated
    }

    public func delete(id: String) async throws {
        try await client.requestEmpty(.delete("/recipes/\(id)"))
        recipes.removeAll { $0.id == id }
    }

    // MARK: - Favourite

    /// Stars / un-stars a recipe. Updates the cached copy in place so every screen
    /// reflects the new state immediately.
    public func setFavorite(id: String, favorite: Bool) async throws {
        try await client.requestEmpty(
            .put("/recipes/\(id)/favorite", body: RecipeFavoritePayload(favorite: favorite))
        )
        if let idx = recipes.firstIndex(where: { $0.id == id }), recipes[idx].isFavorite != favorite {
            recipes[idx] = recipes[idx].togglingFavorite()
        }
    }
}
