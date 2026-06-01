import Biomarkers
import Core
import Foundation
import Observation

/// View model for the home dashboard (Sprint 2).
/// Coordinates biomarker loading, settings persistence, and derived display state.
@MainActor
@Observable
final class DashboardViewModel {

    // MARK: - Local UI state

    var showFlaggedOnly = false
    var isCustomPickerPresented = false

    // MARK: - Derived display state (computed from observable repos)

    var sections: [BiomarkerGroup] {
        groupedByCategory(filteredResults)
    }

    var filteredResults: [BiomarkerWithSeries] {
        var items = filterByDiet(
            biomarkersRepo.results,
            diet: accountRepo.settings.diet,
            customMarkers: Set(accountRepo.settings.customMarkers)
        )
        if showFlaggedOnly {
            items = items.filter { $0.latestResult?.inRange == false }
        }
        return items
    }

    var currentFocus: DietFocus { accountRepo.settings.diet }
    var customMarkers: Set<String> { Set(accountRepo.settings.customMarkers) }
    var allMarkerNames: [String] { biomarkersRepo.results.map(\.biomarker.nameNo).sorted() }

    var isLoading: Bool { biomarkersRepo.isLoading || accountRepo.isLoading }
    var loadError: APIError? { biomarkersRepo.error ?? accountRepo.error }
    var hasData: Bool { !biomarkersRepo.results.isEmpty }

    // MARK: - Dependencies

    private let biomarkersRepo: BiomarkersRepository
    private let accountRepo: AccountRepository

    init(biomarkersRepo: BiomarkersRepository, accountRepo: AccountRepository) {
        self.biomarkersRepo = biomarkersRepo
        self.accountRepo = accountRepo
    }

    // MARK: - Load

    func load() async {
        async let biomarkers: () = biomarkersRepo.loadResults()
        async let settings: () = accountRepo.loadSettings()
        _ = await (biomarkers, settings)
    }

    // MARK: - Diet focus

    func setFocus(_ focus: DietFocus) async {
        let old = accountRepo.settings
        var updated = old
        updated.diet = focus
        if focus != .custom { updated.customMarkers = [] }
        accountRepo.settings = updated
        try? await accountRepo.saveSettings(updated)
    }

    func setCustomMarkers(_ markers: Set<String>) async {
        var updated = accountRepo.settings
        updated.customMarkers = Array(markers).sorted()
        accountRepo.settings = updated
        try? await accountRepo.saveSettings(updated)
    }

    /// Seeds the custom marker set from the currently visible markers of a preset diet,
    /// then switches to .custom — mirrors the web "fork from preset" behaviour.
    func forkToCustom(from focus: DietFocus) async {
        let seeded: Set<String>
        if focus == .all || focus == .custom {
            seeded = Set(biomarkersRepo.results.map(\.biomarker.nameNo))
        } else {
            let visible = filterByDiet(biomarkersRepo.results, diet: focus, customMarkers: [])
            seeded = Set(visible.map(\.biomarker.nameNo))
        }
        var updated = accountRepo.settings
        updated.diet = .custom
        updated.customMarkers = Array(seeded).sorted()
        accountRepo.settings = updated
        try? await accountRepo.saveSettings(updated)
    }
}
