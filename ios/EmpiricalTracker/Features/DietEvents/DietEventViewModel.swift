import Core
import DietEvents
import Foundation
import Observation

/// View model for the DietEventManagerView.
/// Owns form-draft state and delegates persistence to DietEventsRepository.
@MainActor
@Observable
final class DietEventViewModel {

    // MARK: - List state

    var isLoading = false
    var errorMessage: String?

    // MARK: - Form draft (reused for the add-sheet)

    var formLabel = ""
    var formKind: DietEvent.Kind = .diet
    var formStartedOn: Date = .now
    var formIsPeriod = false
    var formEndedOn: Date = .now
    var formNote = ""

    var isFormPresented = false

    // MARK: - Validation

    var formIsValid: Bool {
        !formLabel.trimmingCharacters(in: .whitespaces).isEmpty
            && (!formIsPeriod || formEndedOn >= formStartedOn)
    }

    var endDateError: Bool {
        formIsPeriod && formEndedOn < formStartedOn
    }

    // MARK: - Deps

    private let repo: DietEventsRepository

    init(repo: DietEventsRepository) {
        self.repo = repo
    }

    // MARK: - Actions

    func load() async {
        isLoading = true
        errorMessage = nil
        await repo.load()
        if let err = repo.error { errorMessage = err.localizedDescription }
        isLoading = false
    }

    func submitForm() async {
        guard formIsValid else { return }
        errorMessage = nil
        let payload = DietEventPayload(
            label: formLabel.trimmingCharacters(in: .whitespaces),
            kind: formKind,
            startedOn: Calendar.current.startOfDay(for: formStartedOn),
            endedOn: formIsPeriod ? Calendar.current.startOfDay(for: formEndedOn) : nil,
            note: formNote.isEmpty ? nil : formNote
        )
        do {
            try await repo.create(payload)
            resetForm()
            isFormPresented = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(id: String) async {
        do {
            try await repo.delete(id: id)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func resetForm() {
        formLabel = ""
        formKind = .diet
        formStartedOn = .now
        formIsPeriod = false
        formEndedOn = .now
        formNote = ""
    }

    // MARK: - Convenience passthrough

    var events: [DietEvent] { repo.events }
}
