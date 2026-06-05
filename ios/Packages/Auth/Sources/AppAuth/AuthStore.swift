import Core
import Foundation
import Observation

/// App-wide authentication state. Injected via `AppEnvironment` into the SwiftUI environment.
/// Screens read `authStore.isAuthenticated`; they never call the service directly.
@MainActor
@Observable
public final class AuthStore {

    // MARK: - Published state

    public private(set) var session: StoredSession?
    public private(set) var isLoading = false
    public private(set) var error: AuthError?

    public var isAuthenticated: Bool { session != nil }
    public var userID: String? { session?.userID }
    public var email: String? { session?.email }

    // MARK: - Dependencies

    private let service: any AuthServiceProtocol

    // MARK: - Init

    public init(service: any AuthServiceProtocol) {
        self.service = service
    }

    // MARK: - Actions

    /// Called once at app launch to restore a previously authenticated session from
    /// supabase-swift's in-memory store or the Keychain fallback.
    public func restoreSession() async {
        isLoading = true
        defer { isLoading = false }
        session = await service.restoreSession()
    }

    /// Sign in with email + password. Sets `error` on failure; callers observe `error` for messages.
    public func signIn(email: String, password: String) async {
        guard !isLoading else { return }
        isLoading = true
        error = nil
        defer { isLoading = false }
        do {
            session = try await service.signIn(email: email, password: password)
        } catch let e as AuthError {
            error = e
        } catch {
            self.error = .underlying(error)
        }
    }

    /// Sign out. Clears the session locally even if the remote sign-out call fails —
    /// the user should never be stuck in an authenticated state they can't escape.
    public func signOut() async {
        isLoading = true
        defer { isLoading = false }
        try? await service.signOut()
        session = nil
        error = nil
    }

    /// Returns a currently-valid bearer token for an API call, transparently
    /// refreshing it through the backend if the in-memory token has expired. Keeps the
    /// published `session` snapshot in sync when the backend rotates the token. Returns
    /// `nil` only when there is no session at all.
    public func currentAccessToken() async -> String? {
        guard let current = session else { return nil }
        let token = await service.currentAccessToken()
        if let token, token != current.accessToken {
            session = StoredSession(
                accessToken: token,
                userID:      current.userID,
                email:       current.email
            )
        }
        return token ?? current.accessToken
    }

    /// Called when the backend definitively rejects our token (HTTP 401). Tears the
    /// session down so the app returns to the sign-in screen with a clear
    /// "session expired" message, instead of leaving the user in a broken
    /// authenticated-looking state that only surfaces as cryptic sync errors.
    ///
    /// `session` is cleared synchronously (before the first `await`) so concurrent
    /// 401s from parallel requests collapse into a single expiry.
    public func expireSession() async {
        guard session != nil else { return }
        session = nil
        error = .sessionExpired
        try? await service.signOut()
    }
}

// MARK: - AuthError

public enum AuthError: LocalizedError, Sendable {
    case invalidCredentials
    case networkError
    /// The session token was rejected by the backend after a period of inactivity.
    case sessionExpired
    case underlying(any Error)

    public var errorDescription: String? {
        switch self {
        case .invalidCredentials: return String(localized: "auth.error.invalid_credentials",
                                                bundle: .main)
        case .networkError:       return String(localized: "auth.error.network",
                                                bundle: .main)
        case .sessionExpired:     return String(localized: "auth.error.session_expired",
                                                bundle: .main)
        case .underlying(let e):  return e.localizedDescription
        }
    }
}
