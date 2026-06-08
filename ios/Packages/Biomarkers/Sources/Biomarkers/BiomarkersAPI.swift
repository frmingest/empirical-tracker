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

    /// `POST /biomarkers/import/document` — structure on-device-extracted lab
    /// text into a reviewable candidate (ADR-032). Nothing is written yet.
    public static func importDocument(
        text: String,
        sourceKind: String,
        client: APIClient
    ) async throws -> LabImportCandidate {
        try await client.request(
            .post("/biomarkers/import/document",
                  body: LabDocumentPayload(text: text, sourceKind: sourceKind))
        )
    }

    /// `POST /biomarkers/imports/{id}/apply` — write the reviewed candidate.
    public static func applyLabImport(
        id: String,
        panels: [LabImportPanel],
        client: APIClient
    ) async throws -> LabImportApplyResult {
        try await client.request(
            .post("/biomarkers/imports/\(id)/apply",
                  body: ApplyLabImportPayload(panels: panels))
        )
    }

    /// `DELETE /biomarkers/imports/{id}` — discard a pending candidate.
    public static func discardLabImport(id: String, client: APIClient) async throws {
        try await client.requestEmpty(.delete("/biomarkers/imports/\(id)"))
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
