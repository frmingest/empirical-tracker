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
    /// Set to open the edit sheet for an existing entry.
    var editingEntry: FoodEntry?

    var searchQuery = ""
    var selectedSource: FoodSearchSource = .all

    // MARK: - Error surfacing

    var errorMessage: String?

    // MARK: - Dependencies

    let repo: FoodDiaryRepository
    /// Device-local recents buffer; nil in contexts that don't surface recents.
    private let recents: RecentFoodsStore?
    /// Device-local logging-day record behind the streak line; nil in previews.
    private let activity: LoggingActivityStore?
    private var searchTask: Task<Void, Never>?

    init(
        repo: FoodDiaryRepository,
        recents: RecentFoodsStore? = nil,
        activity: LoggingActivityStore? = nil
    ) {
        self.repo = repo
        self.recents = recents
        self.activity = activity
    }

    // MARK: - Passthrough (observed via the repository)

    var entries: [FoodEntry]            { repo.entries }
    var entriesByMeal: [Meal: [FoodEntry]] { repo.entriesByMeal }
    var dailyTotals: DailyTotals        { repo.dailyTotals }
    var searchResults: [FoodItem]       { repo.searchResults }
    var isLoading: Bool                 { repo.isLoading }
    var isSearching: Bool               { repo.isSearching }
    var hasEntries: Bool                { !repo.entries.isEmpty }
    var recentFoods: [RecentFoodsStore.RecentFood] { recents?.items ?? [] }

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

    // MARK: - Custom food catalogue

    func createCustomFood(_ payload: CustomFoodPayload) async throws -> CustomFoodRecord {
        try await repo.createCustomFood(payload)
    }

    // MARK: - Label parse

    func parseLabel(ocrText: String) async throws -> ParsedLabel {
        try await repo.parseLabel(ocrText: ocrText)
    }

    // MARK: - Persistence

    /// Logs a food, then reloads the day so totals and meal sections stay consistent.
    /// Product-backed logs (`recentItem` non-nil) are recorded in the recents buffer
    /// for one-tap re-logging.
    func log(_ payload: FoodEntryPayload, recentItem: FoodItem? = nil, quantityG: Double? = nil) async {
        do {
            try await repo.create(payload)
            if let recentItem, let quantityG {
                recents?.record(item: recentItem, quantityG: quantityG)
            }
            activity?.recordToday()
            Haptics.success()
            await load()
            isAddPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Copies every entry of the previous day onto the selected day — the
    /// lowest-friction path for repetitive diets. Reads the previous day without
    /// disturbing the loaded day, then re-creates each entry with its provenance.
    func copyPreviousDay() async {
        guard let previous = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) else { return }
        do {
            let previousEntries = try await repo.fetchEntries(date: previous)
            guard !previousEntries.isEmpty else {
                errorMessage = String(localized: "food.copy_yesterday.empty")
                return
            }
            for entry in previousEntries {
                let payload = FoodEntryPayload(
                    loggedOn: selectedDate,
                    meal: entry.meal,
                    foodName: entry.foodName,
                    brand: entry.brand,
                    barcode: entry.barcode,
                    quantityG: entry.quantityG,
                    energyKcal: entry.energyKcal,
                    carbsG: entry.carbsG,
                    proteinG: entry.proteinG,
                    fatG: entry.fatG,
                    saturatedFatG: entry.saturatedFatG,
                    sodiumMg: entry.sodiumMg,
                    source: entry.source,
                    note: entry.note,
                    ingredients: entry.ingredients
                )
                try await repo.create(payload)
            }
            activity?.recordToday()
            Haptics.success()
            await load()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func update(_ entry: FoodEntry, payload: FoodEntryUpdatePayload) async {
        do {
            try await repo.update(id: entry.id, payload: payload)
            editingEntry = nil
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
