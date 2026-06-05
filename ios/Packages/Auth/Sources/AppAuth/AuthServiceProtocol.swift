import Foundation

/// Abstraction over the concrete auth backend (Supabase in production, mock in tests/demo).
/// Conformers are `Sendable` so they can be passed across actor boundaries.
public protocol AuthServiceProtocol: Sendable {
    /// Sign in with email + password. Throws `AuthError` on invalid credentials or network failure.
    func signIn(email: String, password: String) async throws -> StoredSession
    /// Create a new account with email + password and start a session.
    ///
    /// Throws `AuthError.emailAlreadyRegistered` if the address is taken,
    /// `AuthError.weakPassword` if the backend rejects the password, and
    /// `AuthError.emailConfirmationRequired` when the account was created but the
    /// project requires the user to confirm their email before a session is issued
    /// (in that case there is no `StoredSession` to return yet).
    func signUp(email: String, password: String) async throws -> StoredSession
    /// Sign out and revoke the server-side session. Never throws — failure is swallowed locally.
    func signOut() async throws
    /// Returns a valid session if one exists (in-memory, Keychain restore, or token refresh).
    /// Returns `nil` when the user has never signed in or the session has expired irreversibly.
    func restoreSession() async -> StoredSession?
    /// Returns a currently-valid access token, transparently refreshing it via the
    /// backend if the in-memory token has expired. Returns `nil` when no token can be
    /// obtained. Called before each authenticated request so a long-idle session keeps
    /// working without the user noticing.
    func currentAccessToken() async -> String?
}
