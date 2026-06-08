import Core
import Foundation
import Observation

/// Observable in-memory store for biomarker data.
/// View models observe `results` and `panels` directly.
/// Sprint 2 wires this to real API calls; Sprint 11 adds SwiftData offline cache.
@MainActor
@Observable
public final class BiomarkersRepository {
    public var results: [BiomarkerWithSeries] = []
    public var panels: [Panel] = []
    public var isLoading = false
    public var error: APIError?

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Fetch

    public func loadResults() async {
        isLoading = true
        error = nil
        do {
            results = try await BiomarkersAPI.fetchResults(client: client)
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
        isLoading = false
    }

    public func loadPanels() async {
        isLoading = true
        error = nil
        do {
            panels = try await BiomarkersAPI.fetchPanels(client: client)
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
        isLoading = false
    }

    // MARK: - Mutations

    public func addManualResult(_ payload: ManualResultPayload) async throws {
        try await BiomarkersAPI.addManualResult(payload, client: client)
        await loadResults()
    }

    public func deletePanel(id: String) async throws {
        try await BiomarkersAPI.deletePanel(id: id, client: client)
        panels.removeAll { $0.id == id }
        await loadResults()
    }

    public func deleteAllPanels() async throws {
        try await BiomarkersAPI.deleteAllPanels(client: client)
        panels = []
        results = []
    }

    // MARK: - Import

    /// Uploads a .xlsx file to the server and refreshes both panels and results on success.
    /// Progress (0→1) is forwarded to `onProgress` on the MainActor.
    public func importXLSX(
        fileURL: URL,
        importService: BiomarkersImportService,
        onProgress: @MainActor @escaping (Double) -> Void
    ) async throws -> ImportResult {
        let result = try await importService.upload(fileURL: fileURL) { fraction in
            Task { @MainActor in onProgress(fraction) }
        }
        await loadPanels()
        await loadResults()
        return result
    }

    // MARK: - Document import (ADR-032)

    /// Sends on-device-extracted lab text to the server and returns a reviewable
    /// candidate. Nothing is written to the store until `applyLabImport` runs.
    public func importDocument(text: String, sourceKind: String) async throws -> LabImportCandidate {
        try await BiomarkersAPI.importDocument(text: text, sourceKind: sourceKind, client: client)
    }

    /// Applies a reviewed candidate, then refreshes panels and results.
    @discardableResult
    public func applyLabImport(id: String, panels: [LabImportPanel]) async throws -> LabImportApplyResult {
        let result = try await BiomarkersAPI.applyLabImport(id: id, panels: panels, client: client)
        await loadPanels()
        await loadResults()
        return result
    }

    /// Discards a pending candidate without writing anything.
    public func discardLabImport(id: String) async throws {
        try await BiomarkersAPI.discardLabImport(id: id, client: client)
    }

    // MARK: - Filtering helpers

    /// Returns only the markers visible for the given diet focus.
    /// Uses keyword-based matching (DietProfiles) so Norwegian lab name variants are handled.
    public func filtered(by focus: DietFocus, customMarkers: Set<String>) -> [BiomarkerWithSeries] {
        filterByDiet(results, diet: focus, customMarkers: customMarkers)
    }
}
