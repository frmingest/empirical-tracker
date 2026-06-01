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

    // MARK: - GDPR export (Sprint 11)

    /// Returns raw JSON/CSV data for the user to save via share sheet.
    public func exportData(format: ExportFormat) async throws -> Data {
        // Sprint 11: GET /account/export?format=json|csv
        throw APIError.serverError(statusCode: 501, message: "GDPR export available in Sprint 11")
    }

    // MARK: - Account deletion (Sprint 11)

    public func deleteAccount(confirmation: String) async throws {
        guard confirmation == "DELETE" else { return }
        // Sprint 11: DELETE /account
        throw APIError.serverError(statusCode: 501, message: "Account deletion available in Sprint 11")
    }

    public enum ExportFormat: String, Sendable { case json, csv }
}
