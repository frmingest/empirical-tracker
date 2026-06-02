import Foundation

/// Abstraction over the concrete auth backend (Supabase in production, mock in tests/demo).
/// Conformers are `Sendable` so they can be passed across actor boundaries.
public protocol AuthServiceProtocol: Sendable {
    /// Sign in with email + password. Throws `AuthError` on invalid credentials or network failure.
    func signIn(email: String, password: String) async throws -> StoredSession
    /// Sign out and revoke the server-side session. Never throws — failure is swallowed locally.
    func signOut() async throws
    /// Returns a valid session if one exists (in-memory, Keychain restore, or token refresh).
    /// Returns `nil` when the user has never signed in or the session has expired irreversibly.
    func restoreSession() async -> StoredSession?
}
