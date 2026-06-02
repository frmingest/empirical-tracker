import Biomarkers
import Core
import DietEvents
import Foundation
import Observation

/// Drives `BiomarkerDetailView`.
/// Owns diet-event loading (for the chart overlay) and the manual-entry flow.
/// The marker itself is read live from `BiomarkersRepository` so the chart
/// refreshes automatically after a manual result is added.
@MainActor
@Observable
final class BiomarkerDetailViewModel {

    // MARK: - Manual entry sheet

    var isManualEntryPresented = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let biomarkersRepo: BiomarkersRepository
    private let dietEventsRepo: DietEventsRepository

    init(biomarkersRepo: BiomarkersRepository, dietEventsRepo: DietEventsRepository) {
        self.biomarkersRepo = biomarkersRepo
        self.dietEventsRepo = dietEventsRepo
    }

    // MARK: - Loading

    /// Ensures diet events are available for the overlay without re-fetching
    /// if another screen already loaded them.
    func loadOverlayIfNeeded() async {
        if dietEventsRepo.events.isEmpty {
            await dietEventsRepo.load()
        }
    }

    // MARK: - Overlay

    /// Diet events intersecting the marker's measurement window.
    func overlappingEvents(for marker: BiomarkerWithSeries) -> [DietEvent] {
        guard
            let first = marker.series.first?.testedAt,
            let last = marker.series.last?.testedAt
        else { return [] }
        return dietEventsRepo.events(overlapping: first, end: last)
    }

    // MARK: - Manual entry

    /// Adds a manual result to the same biomarker and refreshes the dashboard data.
    func addManualResult(
        to marker: BiomarkerWithSeries,
        value: Double,
        testedAt: Date
    ) async -> Bool {
        let info = marker.biomarker
        let payload = ManualResultPayload(
            biomarkerId: info.id,
            value: value,
            testedAt: testedAt
        )
        do {
            try await biomarkersRepo.addManualResult(payload)
            isManualEntryPresented = false
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }
}
