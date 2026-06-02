import Core
import Foundation

/// DTOs + a thin client for the **Withings Cloud API** connection (Sprint 10, ADR-023).
///
/// This is Path B of the migration plan's two-path Withings strategy (§1.2). The
/// **backend** owns the heavy lifting: the OAuth2 token exchange (`/withings/callback`),
/// the historical `getmeas` pull, token refresh, and the `Notify` webhooks. This client
/// only drives the parts that must originate on-device:
///
/// - **start** the connection — fetch the Withings consent URL the app opens in
///   `ASWebAuthenticationSession` (`GET /withings/authorize`);
/// - **read** connection status + last sync (`GET /withings/connection`);
/// - **trigger** a manual server-side pull (`POST /withings/sync`);
/// - **disconnect** (`DELETE /withings/connection`).
///
/// No Withings credentials or tokens ever touch the device — the app carries only its
/// Supabase JWT, and the backend (Supabase Frankfurt, EU) holds the encrypted Withings
/// tokens. Lives in the `HealthSync` package alongside the Apple Health bridge because
/// both realise the single "health sync" domain module from the migration plan (§1.3);
/// it depends on `Core` only (no HealthKit), so the package still builds everywhere.
public struct WithingsCloudService: Sendable {

    private let client: APIClient

    public init(client: APIClient) {
        self.client = client
    }

    // MARK: - Callback contract

    /// The custom URL scheme the backend redirects to after a successful code→token
    /// exchange. Registered in `Info.plist` (`CFBundleURLTypes`) and handed to
    /// `ASWebAuthenticationSession` as its `callbackURLScheme`.
    public static let callbackScheme = "empiricaltracker"

    /// The host segment of the post-exchange redirect (`empiricaltracker://withings`).
    public static let callbackHost = "withings"

    /// True when `url` is the backend's post-exchange redirect back into the app.
    /// The session may also resolve with a user-cancel; this distinguishes success.
    public static func isSuccessCallback(_ url: URL) -> Bool {
        url.scheme?.lowercased() == callbackScheme
            && url.host?.lowercased() == callbackHost
    }

    // MARK: - Endpoints

    /// Current connection state for the signed-in user. A `404` means the backend
    /// hasn't shipped the Withings Cloud endpoints yet (see `WithingsCloudState`,
    /// which treats that as "feature unavailable" and hides the UI).
    public func status() async throws -> WithingsConnectionStatus {
        try await client.request(.get("/withings/connection"))
    }

    /// Begins the OAuth2 flow: the backend builds the Withings consent URL (scopes
    /// `user.info,user.metrics,user.activity`, `redirect_uri` → `/withings/callback`)
    /// and returns it for the app to present.
    public func authorize() async throws -> WithingsAuthorization {
        try await client.request(.get("/withings/authorize"))
    }

    /// Asks the backend to pull any new measurements now (the reliable fallback to
    /// webhook delivery, mirroring Apple Health's "Sync now").
    @discardableResult
    public func sync() async throws -> WithingsSyncResult {
        try await client.request(Endpoint(method: .post, path: "/withings/sync"))
    }

    /// Revokes the connection server-side (deletes the stored Withings tokens).
    /// Readings already imported into `body_metrics` are kept.
    public func disconnect() async throws {
        try await client.requestEmpty(.delete("/withings/connection"))
    }
}

// MARK: - DTOs

/// Connection status for the signed-in user, from `GET /withings/connection`.
public struct WithingsConnectionStatus: Decodable, Sendable, Equatable {
    public let connected: Bool
    public let lastSyncAt: Date?
    public let connectedAt: Date?

    public init(connected: Bool, lastSyncAt: Date? = nil, connectedAt: Date? = nil) {
        self.connected = connected
        self.lastSyncAt = lastSyncAt
        self.connectedAt = connectedAt
    }
}

/// The Withings consent URL to present, from `GET /withings/authorize`. `state` is the
/// CSRF token the backend minted and will verify on the callback; the app just carries
/// it through the web session and never inspects it.
public struct WithingsAuthorization: Decodable, Sendable, Equatable {
    public let authorizeUrl: URL
    public let state: String?

    public init(authorizeUrl: URL, state: String? = nil) {
        self.authorizeUrl = authorizeUrl
        self.state = state
    }
}

/// Result summary of a manual server-side pull, from `POST /withings/sync`.
public struct WithingsSyncResult: Decodable, Sendable, Equatable {
    public let imported: Int
    public let duplicatesSkipped: Int

    public var isEmpty: Bool { imported == 0 }

    public init(imported: Int, duplicatesSkipped: Int) {
        self.imported = imported
        self.duplicatesSkipped = duplicatesSkipped
    }
}
