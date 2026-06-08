import Biomarkers
import Core
import Foundation
import Observation

/// Drives the lab-import review screen (ADR-032 Phase 1).
///
/// A document import is probabilistic and medical, so the server stages it as a
/// *candidate* and never writes until the user reviews and applies it here. The
/// model holds an editable copy of the candidate: the user can correct values,
/// set each panel's draw date (required before apply), and uncheck rows.
///
/// Phase 1 applies numeric results only; qualitative rows (e.g. "Positiv") are
/// surfaced read-only and excluded until `results.value_text` ships (Phase 3).
@MainActor
@Observable
final class LabImportReviewModel: Identifiable {

    // MARK: - Editable state

    struct Row: Identifiable {
        let id: UUID
        var nameNo: String
        /// User-editable numeric value as text ("" when qualitative/unreadable).
        var valueText: String
        var unit: String?
        var refRangeRaw: String?
        /// Non-nil for qualitative results we can't yet store (shown, not applied).
        let qualitativeText: String?
        var include: Bool

        var isQualitative: Bool { qualitativeText != nil }

        var parsedValue: Double? {
            let normalized = valueText.replacingOccurrences(of: ",", with: ".")
                .trimmingCharacters(in: .whitespaces)
            return Double(normalized)
        }
    }

    struct PanelEdit: Identifiable {
        let id: UUID
        var date: Date?
        var rows: [Row]
    }

    let id = UUID()
    var panels: [PanelEdit]
    var isApplying = false
    var errorMessage: String?

    private let importId: String
    private let repo: BiomarkersRepository
    private let onApplied: (LabImportApplyResult) -> Void
    private let onDiscarded: () -> Void

    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    init(
        candidate: LabImportCandidate,
        repo: BiomarkersRepository,
        onApplied: @escaping (LabImportApplyResult) -> Void,
        onDiscarded: @escaping () -> Void
    ) {
        self.importId = candidate.importId
        self.repo = repo
        self.onApplied = onApplied
        self.onDiscarded = onDiscarded
        self.panels = candidate.panels.map { panel in
            PanelEdit(
                id: panel.id,
                date: panel.testedAt.flatMap { Self.dayFormatter.date(from: $0) },
                rows: panel.results.map { r in
                    Row(
                        id: r.id,
                        nameNo: r.nameNo,
                        valueText: r.value.map { Self.format($0) } ?? "",
                        unit: r.unit,
                        refRangeRaw: r.refRangeRaw,
                        qualitativeText: r.value == nil ? r.valueText : nil,
                        include: r.value != nil  // numeric rows pre-selected
                    )
                }
            )
        }
    }

    // MARK: - Derived

    /// Numeric, included rows that will actually be written.
    private func applicableRows(in panel: PanelEdit) -> [Row] {
        panel.rows.filter { $0.include && !$0.isQualitative && $0.parsedValue != nil }
    }

    /// Apply is allowed once at least one row is selected and every panel that
    /// has selected rows also has a date set.
    var canApply: Bool {
        let active = panels.filter { !applicableRows(in: $0).isEmpty }
        return !active.isEmpty && active.allSatisfy { $0.date != nil }
    }

    var selectedCount: Int {
        panels.reduce(0) { $0 + applicableRows(in: $1).count }
    }

    // MARK: - Actions

    func apply() async {
        guard canApply else { return }
        isApplying = true
        errorMessage = nil
        defer { isApplying = false }

        let payloadPanels: [LabImportPanel] = panels.compactMap { panel in
            let rows = applicableRows(in: panel)
            guard let date = panel.date, !rows.isEmpty else { return nil }
            return LabImportPanel(
                testedAt: Self.dayFormatter.string(from: date),
                results: rows.map { row in
                    LabImportResult(
                        nameNo: row.nameNo,
                        value: row.parsedValue,
                        unit: row.unit,
                        refRangeRaw: row.refRangeRaw
                    )
                }
            )
        }

        do {
            let result = try await repo.applyLabImport(id: importId, panels: payloadPanels)
            onApplied(result)
        } catch let e as APIError {
            errorMessage = Self.message(for: e)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func discard() async {
        // Best-effort: even if the network discard fails, drop the local review.
        try? await repo.discardLabImport(id: importId)
        onDiscarded()
    }

    // MARK: - Helpers

    private static func format(_ value: Double) -> String {
        if value == value.rounded() {
            return String(Int(value))
        }
        return String(value)
    }

    private static func message(for error: APIError) -> String {
        switch error {
        case .serverError(409, _):
            return "This import was already applied or discarded."
        case .serverError(_, let detail):
            return detail ?? "The import couldn't be applied. Please try again."
        case .unauthorized:
            return "Your session expired. Please sign in again."
        default:
            return error.localizedDescription
        }
    }
}
