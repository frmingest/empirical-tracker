import Core
import Foundation

/// Typed wrappers around every biomarker-related endpoint.
/// Mirrors all routes under `/biomarkers` in `api/app/biomarkers/router.py`.
public enum BiomarkersAPI {

    /// `GET /biomarkers/results` — full time-series for every biomarker.
    public static func fetchResults(client: APIClient) async throws -> [BiomarkerWithSeries] {
        try await client.request(.get("/biomarkers/results"))
    }

    /// `GET /biomarkers` — flat biomarker list (no series data).
    public static func fetchBiomarkers(client: APIClient) async throws -> [BiomarkerInfo] {
        try await client.request(.get("/biomarkers"))
    }

    /// `GET /biomarkers/panels` — list of blood-draw sessions.
    public static func fetchPanels(client: APIClient) async throws -> [Panel] {
        try await client.request(.get("/biomarkers/panels"))
    }

    /// `POST /biomarkers/results/manual` — add a single manual result.
    public static func addManualResult(
        _ payload: ManualResultPayload,
        client: APIClient
    ) async throws {
        try await client.requestEmpty(.post("/biomarkers/results/manual", body: payload))
    }

    /// `DELETE /biomarkers/import/{panelId}` — remove one panel and its results.
    public static func deletePanel(id: String, client: APIClient) async throws {
        try await client.requestEmpty(.delete("/biomarkers/import/\(id)"))
    }

    /// `DELETE /biomarkers/import` — remove **all** panels (and results) for the user.
    public static func deleteAllPanels(client: APIClient) async throws {
        try await client.requestEmpty(.delete("/biomarkers/import"))
    }
}
