import Core

/// Bridges `AuthStore` to `APIClient`'s `TokenProvider` protocol.
///
/// `AuthStore` is `@MainActor`-isolated, so we hop to the main actor each time
/// `APIClient` (an actor) calls `currentToken()`. This is safe and cheap —
/// it's a single property read with no I/O.
public final class AuthTokenProvider: TokenProvider, Sendable {

    // @MainActor-isolated classes are implicitly Sendable (Swift SE-0316).
    private let authStore: AuthStore

    public init(authStore: AuthStore) {
        self.authStore = authStore
    }

    public func currentToken() async -> String? {
        // Routes through AuthStore → auth backend so an access token that expired
        // while the app was idle is refreshed before the request goes out, rather
        // than sending a stale token and failing with a 401.
        await authStore.currentAccessToken()
    }
}
