import Core
import Foundation
import Observation

/// Meal plans + calendar CRUD, plus the shared food-search proxy used by the
/// planned-meal picker. Mirrors every route under `/meal-plans` in
/// `api/app/meal_plans/router.py` (ADR-012), and reuses the food-diary
/// search / barcode endpoints (ADR-018 / ADR-019) — never calling OFF directly.
@MainActor
@Observable
public final class MealPlansRepository {

    // MARK: - State

    /// Named plans (the groupings/labels).
    public var plans: [MealPlan] = []
    /// Planned meals for the currently-loaded calendar window.
    public var meals: [PlannedMeal] = []
    /// Search results for the planned-meal picker (reuses the food proxy).
    public var searchResults: [FoodItem] = []

    public var isLoading = false
    public var isSearching = false
    public var error: APIError?

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Named plans

    public func loadPlans() async {
        do {
            plans = try await client.request(.get("/meal-plans"))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
    }

    public func createPlan(_ payload: MealPlanPayload) async throws {
        let created: MealPlan = try await client.request(.post("/meal-plans", body: payload))
        plans.append(created)
    }

    /// Deletes the plan *label* only. Its scheduled meals stay on the calendar,
    /// un-grouped (`plan_id` is `ON DELETE SET NULL` — ADR-012).
    public func deletePlan(id: String) async throws {
        try await client.requestEmpty(.delete("/meal-plans/\(id)"))
        plans.removeAll { $0.id == id }
        // Reflect the SET NULL locally so the calendar doesn't show a dangling plan.
        meals = meals.map { meal in
            guard meal.planId == id else { return meal }
            return PlannedMeal(
                id: meal.id, scheduledOn: meal.scheduledOn, meal: meal.meal,
                foodName: meal.foodName, brand: meal.brand, barcode: meal.barcode,
                quantityG: meal.quantityG, energyKcal: meal.energyKcal,
                carbsG: meal.carbsG, proteinG: meal.proteinG, fatG: meal.fatG,
                note: meal.note, done: meal.done, planId: nil
            )
        }
    }

    // MARK: - Calendar (one week at a time)

    public func loadCalendar(week: PlanWeek) async {
        isLoading = true
        error = nil
        do {
            let query = [
                URLQueryItem(name: "start", value: ISO8601DateFormatter.dateOnly.string(from: week.start)),
                URLQueryItem(name: "end", value: ISO8601DateFormatter.dateOnly.string(from: week.end)),
            ]
            meals = try await client.request(.get("/meal-plans/calendar", query: query))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
        isLoading = false
    }

    public func schedule(_ payload: PlannedMealPayload) async throws {
        let created: PlannedMeal = try await client.request(.post("/meal-plans/calendar", body: payload))
        meals.append(created)
    }

    /// Toggles the cooked/eaten flag (`PATCH /meal-plans/calendar/{id}`).
    public func setDone(id: String, done: Bool) async throws {
        let updated: PlannedMeal = try await client.request(
            .patch("/meal-plans/calendar/\(id)", body: PlannedMealDonePayload(done: done))
        )
        if let idx = meals.firstIndex(where: { $0.id == id }) {
            meals[idx] = updated
        }
    }

    public func deleteMeal(id: String) async throws {
        try await client.requestEmpty(.delete("/meal-plans/calendar/\(id)"))
        meals.removeAll { $0.id == id }
    }

    // MARK: - Log a planned meal to the diary

    /// Promotes a planned meal into the food diary as a real entry and marks it
    /// `done`. Reuses `POST /food-diary` — no new backend surface (ADR-012).
    public func logToDiary(_ meal: PlannedMeal, on date: Date? = nil) async throws {
        try await client.requestEmpty(.post("/food-diary", body: meal.diaryPayload(loggedOn: date)))
        if !meal.done { try await setDone(id: meal.id, done: true) }
    }

    // MARK: - Food search proxy (shared with the diary — ADR-018 / ADR-019)

    public func search(query: String, source: FoodSearchSource = .mvt) async {
        guard !query.trimmingCharacters(in: .whitespaces).isEmpty else {
            searchResults = []
            return
        }
        isSearching = true
        do {
            searchResults = try await client.request(
                .get("/food-diary/search", query: [
                    URLQueryItem(name: "q", value: query),
                    URLQueryItem(name: "source", value: source.queryValue),
                ])
            )
        } catch {
            searchResults = []
        }
        isSearching = false
    }

    public func lookup(barcode: String) async throws -> FoodItem? {
        do {
            return try await client.request(.get("/food-diary/barcode/\(barcode)"))
        } catch APIError.notFound {
            return nil
        }
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
