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
            let dateStr = ISO8601DateFormatter.dateOnly.string(from: date)
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

    // MARK: - Delete

    public func delete(id: String) async throws {
        try await client.requestEmpty(.delete("/food-diary/\(id)"))
        entries.removeAll { $0.id == id }
    }

    // MARK: - Open Food Facts search (via backend proxy)

    public func search(query: String) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            let items: [FoodItem] = try await client.request(
                .get("/food-diary/search", query: [URLQueryItem(name: "q", value: query)])
            )
            searchResults = items
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    /// Barcode lookup via backend proxy (`GET /food-diary/barcode/{code}`).
    public func lookup(barcode: String) async throws -> FoodItem? {
        do {
            return try await client.request(.get("/food-diary/barcode/\(barcode)"))
        } catch APIError.notFound {
            return nil
        }
    }

    // MARK: - Computed

    public var dailyTotals: DailyTotals {
        DailyTotals.compute(from: entries)
    }

    public var entriesByMeal: [Meal: [FoodEntry]] {
        Dictionary(grouping: entries, by: \.meal)
    }
}

// MARK: - Date helper

private extension ISO8601DateFormatter {
    static let dateOnly: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        return f
    }()
}
