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
        await MainActor.run { authStore.session?.accessToken }
    }
}
