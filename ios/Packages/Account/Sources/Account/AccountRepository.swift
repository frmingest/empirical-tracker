import Core
import Foundation
import Observation

/// Account-level operations: settings, GDPR export, account deletion.
/// Mirrors `GET/PUT /settings` and Sprint 11 `GET /account/export`, `DELETE /account`.
@MainActor
@Observable
public final class AccountRepository {
    public var settings: UserSettings = .default
    public var isLoading = false
    public var error: APIError?

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Settings

    public func loadSettings() async {
        isLoading = true
        defer { isLoading = false }
        do {
            settings = try await client.request(.get("/settings"))
        } catch let e as APIError {
            error = e
        } catch {
            self.error = .networkError(error)
        }
    }

    public func saveSettings(_ updated: UserSettings) async throws {
        settings = updated
        try await client.requestEmpty(.put("/settings", body: updated))
    }

    // MARK: - GDPR export (GDPR Art. 20 — data portability)

    /// Downloads all of the user's data for them to save via the share sheet.
    /// `GET /account/export?format=json|csv`. JSON returns a single document;
    /// CSV returns a zip archive with one CSV per table plus `export_meta.json`.
    public func exportData(format: ExportFormat) async throws -> Data {
        try await client.requestData(
            .get("/account/export", query: [URLQueryItem(name: "format", value: format.rawValue)])
        )
    }

    // MARK: - Account deletion (GDPR Art. 17 — right to erasure)

    /// Permanently erases the user's data and account. `DELETE /account`.
    /// The caller must pass the literal string `"DELETE"`; any other value is a no-op,
    /// guarding against an accidental call that isn't gated by the type-to-confirm UI.
    public func deleteAccount(confirmation: String) async throws {
        guard confirmation == "DELETE" else { return }
        try await client.requestEmpty(.delete("/account"))
    }

    public enum ExportFormat: String, Sendable { case json, csv }
}
