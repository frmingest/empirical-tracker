import Core
import FoodDiary
import Foundation
import Observation

/// View model for the food diary (Sprint 6).
/// Owns the selected day, search-draft state, and presentation flags; delegates all
/// persistence and the multi-source search proxy to `FoodDiaryRepository`.
@MainActor
@Observable
final class FoodDiaryViewModel {

    // MARK: - Day navigation

    var selectedDate: Date = Calendar.current.startOfDay(for: .now)

    // MARK: - Add / search draft state

    var isAddPresented = false
    /// Meal the add-sheet should default to (set from the "+" the user tapped).
    var addTargetMeal: Meal = .breakfast

    var searchQuery = ""
    var selectedSource: FoodSearchSource = .mvt

    // MARK: - Error surfacing

    var errorMessage: String?

    // MARK: - Dependencies

    private let repo: FoodDiaryRepository
    private var searchTask: Task<Void, Never>?

    init(repo: FoodDiaryRepository) {
        self.repo = repo
    }

    // MARK: - Passthrough (observed via the repository)

    var entries: [FoodEntry]            { repo.entries }
    var entriesByMeal: [Meal: [FoodEntry]] { repo.entriesByMeal }
    var dailyTotals: DailyTotals        { repo.dailyTotals }
    var searchResults: [FoodItem]       { repo.searchResults }
    var isLoading: Bool                 { repo.isLoading }
    var isSearching: Bool               { repo.isSearching }
    var hasEntries: Bool                { !repo.entries.isEmpty }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    // MARK: - Load

    func load() async {
        await repo.load(date: selectedDate)
        if let err = repo.error { errorMessage = err.localizedDescription }
    }

    // MARK: - Day navigation

    func goToPreviousDay() async { await shiftDay(by: -1) }
    func goToNextDay() async     { await shiftDay(by: 1) }

    func goToToday() async {
        selectedDate = Calendar.current.startOfDay(for: .now)
        await load()
    }

    private func shiftDay(by days: Int) async {
        guard let next = Calendar.current.date(byAdding: .day, value: days, to: selectedDate) else { return }
        selectedDate = Calendar.current.startOfDay(for: next)
        await load()
    }

    // MARK: - Add entry point

    func beginAdd(meal: Meal) {
        addTargetMeal = meal
        searchQuery = ""
        repo.searchResults = []
        isAddPresented = true
    }

    // MARK: - Search (debounced ~400 ms; ignores stale responses via task cancellation)

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

    /// Re-run the current query immediately (e.g. after the source selector changes).
    func searchNow() async {
        searchTask?.cancel()
        await repo.search(query: searchQuery, source: selectedSource)
    }

    // MARK: - Barcode

    func lookup(barcode: String) async throws -> FoodItem? {
        try await repo.lookup(barcode: barcode)
    }

    // MARK: - Persistence

    /// Logs a food, then reloads the day so totals and meal sections stay consistent.
    func log(_ payload: FoodEntryPayload) async {
        do {
            try await repo.create(payload)
            await load()
            isAddPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(_ entry: FoodEntry) async {
        do {
            try await repo.delete(id: entry.id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Day formatting

    var dayTitle: String {
        if isToday { return String(localized: "food.day.today") }
        if Calendar.current.isDateInYesterday(selectedDate) { return String(localized: "food.day.yesterday") }
        return selectedDate.formatted(.dateTime.weekday(.wide).day().month(.abbreviated))
    }
}
