import Biomarkers
import Core
import Foundation
import Observation

/// Drives the panel timeline screen.
/// Derives flagged marker names by cross-referencing the panel draw date
/// against the full biomarker series stored in `BiomarkersRepository`.
@MainActor
@Observable
final class PanelTimelineViewModel {

    // MARK: - Observable state

    /// Panels sorted newest-first.
    var panels: [Panel] { biomarkersRepo.panels.sorted { $0.testedAt > $1.testedAt } }
    var isLoading: Bool { biomarkersRepo.isLoading }
    var error: APIError? { biomarkersRepo.error }

    // MARK: - Delete confirmation

    var panelPendingDelete: Panel?
    var isDeleteAllConfirmationPresented = false

    // MARK: - Dependencies

    private let biomarkersRepo: BiomarkersRepository

    init(biomarkersRepo: BiomarkersRepository) {
        self.biomarkersRepo = biomarkersRepo
    }

    // MARK: - Load

    func load() async {
        await biomarkersRepo.loadPanels()
    }

    // MARK: - Flagged markers

    /// Returns the Norwegian names of out-of-range biomarkers measured on the same
    /// calendar day as `panel.testedAt`. Uses the existing results series — no extra
    /// network call required.
    func flaggedMarkerNames(for panel: Panel) -> [String] {
        let cal = Calendar.current
        let day = cal.startOfDay(for: panel.testedAt)

        return biomarkersRepo.results.compactMap { series in
            let hasOutOfRange = series.series.contains { point in
                cal.startOfDay(for: point.testedAt) == day && point.inRange == false
            }
            return hasOutOfRange ? series.biomarker.displayName : nil
        }.sorted()
    }

    // MARK: - Delete

    func confirmDelete(_ panel: Panel) {
        panelPendingDelete = panel
    }

    func executeDelete() async {
        guard let panel = panelPendingDelete else { return }
        panelPendingDelete = nil
        do {
            try await biomarkersRepo.deletePanel(id: panel.id)
        } catch {
            // Silently log; the UI will show the panel still present if it failed.
            // A future sprint can surface this through a toast.
        }
    }

    func cancelDelete() {
        panelPendingDelete = nil
    }

    func executeDeleteAll() async {
        isDeleteAllConfirmationPresented = false
        do {
            try await biomarkersRepo.deleteAllPanels()
        } catch {
            // Same approach as single delete.
        }
    }
}
