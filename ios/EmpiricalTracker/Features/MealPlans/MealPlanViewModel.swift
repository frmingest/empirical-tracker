import Core
import MealPlans
import Foundation
import Observation

/// View model for the Plan tab (Sprint 7). Owns the visible week, the plan filter,
/// and picker draft state; delegates all persistence and the shared food-search
/// proxy to `MealPlansRepository`.
@MainActor
@Observable
final class MealPlanViewModel {

    // MARK: - Week navigation

    var week = PlanWeek(containing: .now)

    // MARK: - Plan filter

    /// `nil` shows every meal in the week; otherwise only meals in this plan.
    var selectedPlanId: String?

    // MARK: - Scheduling draft

    var isPickerPresented = false
    var isPlanManagerPresented = false
    /// Day the picker should schedule onto (set from the "+" the user tapped).
    var addTargetDate: Date = Calendar.current.startOfDay(for: .now)
    var addTargetMeal: Meal = .breakfast

    var searchQuery = ""
    var selectedSource: FoodSearchSource = .all

    // MARK: - Error surfacing

    var errorMessage: String?

    // MARK: - Dependencies

    private let repo: MealPlansRepository
    private var searchTask: Task<Void, Never>?

    init(repo: MealPlansRepository) {
        self.repo = repo
    }

    // MARK: - Passthrough

    var plans: [MealPlan]            { repo.plans }
    var allMeals: [PlannedMeal]      { repo.meals }
    var searchResults: [FoodItem]    { repo.searchResults }
    var isLoading: Bool              { repo.isLoading }
    var isSearching: Bool            { repo.isSearching }

    /// The plan currently used as the filter, if any.
    var selectedPlan: MealPlan? {
        guard let id = selectedPlanId else { return nil }
        return plans.first { $0.id == id }
    }

    // MARK: - Load

    func load() async {
        await repo.loadPlans()
        await repo.loadCalendar(week: week)
        surfaceError()
    }

    // MARK: - Week navigation

    func goToPreviousWeek() async { await shiftWeek(by: -1) }
    func goToNextWeek() async     { await shiftWeek(by: 1) }

    func goToThisWeek() async {
        week = PlanWeek(containing: .now)
        await repo.loadCalendar(week: week)
        surfaceError()
    }

    private func shiftWeek(by offset: Int) async {
        week = week.shifted(by: offset)
        await repo.loadCalendar(week: week)
        surfaceError()
    }

    var isCurrentWeek: Bool {
        week == PlanWeek(containing: .now)
    }

    // MARK: - Calendar derivation

    /// Meals for `day`, honouring the active plan filter, ordered by meal slot.
    func meals(on day: Date) -> [PlannedMeal] {
        let cal = Calendar.current
        return allMeals
            .filter { cal.isDate($0.scheduledOn, inSameDayAs: day) }
            .filter { selectedPlanId == nil || $0.planId == selectedPlanId }
            .sorted { mealOrder($0.meal) < mealOrder($1.meal) }
    }

    /// Sum of energy for the day's (filtered) meals — present values only, never estimated.
    func energyTotal(on day: Date) -> Double {
        meals(on: day).compactMap(\.energyKcal).reduce(0, +)
    }

    /// True when the visible week, under the active filter, has no scheduled meals.
    var isWeekEmpty: Bool {
        week.days.allSatisfy { meals(on: $0).isEmpty }
    }

    private func mealOrder(_ meal: Meal) -> Int {
        Meal.allCases.firstIndex(of: meal) ?? Meal.allCases.count
    }

    // MARK: - Scheduling entry point

    func beginAdd(on day: Date, meal: Meal) {
        addTargetDate = Calendar.current.startOfDay(for: day)
        addTargetMeal = meal
        searchQuery = ""
        repo.searchResults = []
        isPickerPresented = true
    }

    // MARK: - Search (debounced ~400 ms; stale responses dropped via cancellation)

    func scheduleSearch() {
        searchTask?.cancel()
        let query = searchQuery
        let source = selectedSource
        searchTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 400_000_000)
            guard !Task.isCancelled else { return }
            await self?.repo.search(query: query, source: source)
        }
    }

    func searchNow() async {
        searchTask?.cancel()
        await repo.search(query: searchQuery, source: selectedSource)
    }

    func lookup(barcode: String) async throws -> FoodItem? {
        try await repo.lookup(barcode: barcode)
    }

    // MARK: - Persistence

    /// Schedules a meal, attaching it to the active plan filter (if any), then closes
    /// the picker. Reloads so the calendar stays consistent.
    func schedule(item: FoodItem, quantityG: Double, note: String?) async {
        let payload = PlannedMealPayload(
            scheduledOn: addTargetDate,
            meal: addTargetMeal,
            item: item,
            quantityG: quantityG,
            planId: selectedPlanId,
            note: note
        )
        await persistSchedule(payload)
    }

    func scheduleFreeText(
        name: String,
        quantityG: Double?,
        energyKcal: Double?,
        carbsG: Double?,
        proteinG: Double?,
        fatG: Double?,
        note: String?
    ) async {
        let payload = PlannedMealPayload(
            scheduledOn: addTargetDate,
            meal: addTargetMeal,
            foodName: name,
            quantityG: quantityG,
            energyKcal: energyKcal,
            carbsG: carbsG,
            proteinG: proteinG,
            fatG: fatG,
            planId: selectedPlanId,
            note: note
        )
        await persistSchedule(payload)
    }

    private func persistSchedule(_ payload: PlannedMealPayload) async {
        do {
            try await repo.schedule(payload)
            isPickerPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func toggleDone(_ meal: PlannedMeal) async {
        do {
            try await repo.setDone(id: meal.id, done: !meal.done)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ meal: PlannedMeal) async {
        do {
            try await repo.deleteMeal(id: meal.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func logToDiary(_ meal: PlannedMeal) async {
        do {
            try await repo.logToDiary(meal)
            Haptics.success()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Named plans

    func createPlan(name: String, description: String?) async {
        do {
            try await repo.createPlan(MealPlanPayload(name: name, description: description))
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func deletePlan(_ plan: MealPlan) async {
        do {
            try await repo.deletePlan(id: plan.id)
            if selectedPlanId == plan.id { selectedPlanId = nil }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Week formatting

    /// e.g. "2–8 Jun" or "30 Jun – 6 Jul" — a compact week-range label.
    var weekTitle: String {
        let start = week.start
        let end = week.end
        let cal = Calendar.current
        let sameMonth = cal.isDate(start, equalTo: end, toGranularity: .month)
        if sameMonth {
            let startDay = start.formatted(.dateTime.day())
            return "\(startDay)–\(end.formatted(.dateTime.day().month(.abbreviated)))"
        }
        return "\(start.formatted(.dateTime.day().month(.abbreviated))) – \(end.formatted(.dateTime.day().month(.abbreviated)))"
    }

    func dayTitle(_ day: Date) -> String {
        day.formatted(.dateTime.weekday(.wide))
    }

    func daySubtitle(_ day: Date) -> String {
        day.formatted(.dateTime.day().month(.abbreviated))
    }

    func isToday(_ day: Date) -> Bool {
        Calendar.current.isDateInToday(day)
    }

    // MARK: - Helpers

    private func surfaceError() {
        if let err = repo.error { errorMessage = err.localizedDescription }
    }
}
