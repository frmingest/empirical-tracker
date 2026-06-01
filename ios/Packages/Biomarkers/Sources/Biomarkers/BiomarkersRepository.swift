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

    // MARK: - Filtering helpers

    /// Returns only the markers visible for the given diet focus.
    public func filtered(by focus: DietFocus, customMarkers: Set<String>) -> [BiomarkerWithSeries] {
        switch focus {
        case .all:
            return results
        case .custom:
            return results.filter { customMarkers.contains($0.biomarker.nameNo) }
        default:
            guard let set = DietFocus.markerSets[focus] else { return results }
            return results.filter { set.contains($0.biomarker.nameNo) }
        }
    }
}
