import Core
import Foundation
import Observation

/// Food diary CRUD + Open Food Facts search proxy.
/// Mirrors all routes under `/food-diary` in `api/app/food_diary/router.py`.
@MainActor
@Observable
public final class FoodDiaryRepository {
    public var entries: [FoodEntry] = []
    public var searchResults: [FoodItem] = []
    public var isLoading = false
    public var isSearching = false
    public var error: APIError?

    private let client: APIClient
    private var currentDate: Date = Calendar.current.startOfDay(for: .now)

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Fetch

    public func load(date: Date) async {
        currentDate = date
        isLoading = true
        error = nil
        do {
            // Format the diary day in the *current* time zone (CalendarDate). A UTC
            // formatter would resolve local midnight to the previous calendar day for
            // positive-offset zones, fetching yesterday's entries as "today".
            let dateStr = CalendarDate.string(from: date)
            let query = [URLQueryItem(name: "date", value: dateStr)]
            entries = try await client.request(.get("/food-diary", query: query))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
        isLoading = false
    }

    // MARK: - Create

    public func create(_ payload: FoodEntryPayload) async throws {
        let entry: FoodEntry = try await client.request(.post("/food-diary", body: payload))
        entries.append(entry)
    }

    // MARK: - Update

    public func update(id: String, payload: FoodEntryUpdatePayload) async throws {
        let updated: FoodEntry = try await client.request(.put("/food-diary/\(id)", body: payload))
        if let idx = entries.firstIndex(where: { $0.id == id }) {
            entries[idx] = updated
        }
    }

    // MARK: - Delete

    public func delete(id: String) async throws {
        try await client.requestEmpty(.delete("/food-diary/\(id)"))
        entries.removeAll { $0.id == id }
    }

    // MARK: - Multi-source search (via backend proxy)

    /// Full-text search against the selected source (Matvaretabellen / USDA / Open Food
    /// Facts / all). Mirrors `GET /food-diary/search?q=…&source=…` (ADR-018).
    public func search(query: String, source: FoodSearchSource = .all) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            let items: [FoodItem] = try await client.request(
                .get("/food-diary/search", query: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "source", value: source.queryValue),
                ])
            )
            searchResults = items
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    /// Barcode lookup via backend proxy (`GET /food-diary/barcode/{code}`).
    /// Returns nil when the barcode is not found in any source (404).
    public func lookup(barcode: String) async throws -> FoodItem? {
        do {
            return try await client.request(.get("/food-diary/barcode/\(barcode)"))
        } catch APIError.notFound {
            return nil
        }
    }

    // MARK: - Label parse (OCR → structured nutrients)

    /// Sends raw OCR text to the backend for Claude Haiku to extract per-100g nutrients.
    /// Returns a partial `FoodItem` (nil fields for values not found in the label).
    public func parseLabel(ocrText: String) async throws -> ParsedLabel {
        struct Body: Encodable { let ocrText: String }
        return try await client.request(.post("/food-diary/parse-label", body: Body(ocrText: ocrText)))
    }

    // MARK: - Custom food catalogue

    public func createCustomFood(_ payload: CustomFoodPayload) async throws -> CustomFoodRecord {
        try await client.request(.post("/food-diary/custom", body: payload))
    }

    public func updateCustomFood(id: String, _ payload: CustomFoodPayload) async throws -> CustomFoodRecord {
        try await client.request(.put("/food-diary/custom/\(id)", body: payload))
    }

    public func deleteCustomFood(id: String) async throws {
        try await client.requestEmpty(.delete("/food-diary/custom/\(id)"))
    }

    // MARK: - Computed

    public var dailyTotals: DailyTotals {
        DailyTotals.compute(from: entries)
    }

    public var entriesByMeal: [Meal: [FoodEntry]] {
        Dictionary(grouping: entries, by: \.meal)
    }
}
