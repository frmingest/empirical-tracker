import Foundation
import Supabase

/// Production `AuthServiceProtocol` implementation backed by `supabase-swift`.
///
/// Credentials are injected at init time — read them from `Info.plist` entries
/// `SupabaseURL` and `SupabaseAnonKey` (set via Xcode build settings / xcconfig).
/// See `AppConfig.swift` in the app target for how to wire this.
public struct SupabaseAuthService: AuthServiceProtocol {

    private let client: SupabaseClient

    public init(supabaseURL: URL, supabaseAnonKey: String) {
        self.client = SupabaseClient(
            supabaseURL: supabaseURL,
            supabaseKey: supabaseAnonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }

    // MARK: - AuthServiceProtocol

    public func signIn(email: String, password: String) async throws -> StoredSession {
        do {
            let session = try await client.auth.signIn(
                email: email,
                password: password
            )
            let stored = StoredSession(
                accessToken: session.accessToken,
                userID:      session.user.id.uuidString,
                email:       session.user.email ?? email
            )
            KeychainService.save(session: stored)
            return stored
        } catch {
            throw mapError(error)
        }
    }

    public func signUp(email: String, password: String) async throws -> StoredSession {
        do {
            let response = try await client.auth.signUp(email: email, password: password)
            // When the project has "Confirm email" enabled, signUp succeeds but no
            // session is issued until the user clicks the confirmation link. Surface
            // that as a dedicated flow signal rather than a generic failure.
            guard let session = response.session else {
                throw AuthError.emailConfirmationRequired
            }
            let stored = StoredSession(
                accessToken: session.accessToken,
                userID:      session.user.id.uuidString,
                email:       session.user.email ?? email
            )
            KeychainService.save(session: stored)
            return stored
        } catch let error as AuthError {
            throw error
        } catch {
            throw mapSignUpError(error)
        }
    }

    public func signOut() async throws {
        try await client.auth.signOut()
        KeychainService.deleteSession()
    }

    public func restoreSession() async -> StoredSession? {
        // supabase-swift auto-refreshes the access token if the refresh token is valid.
        if let session = try? await client.auth.session {
            let stored = StoredSession(
                accessToken: session.accessToken,
                userID:      session.user.id.uuidString,
                email:       session.user.email ?? ""
            )
            KeychainService.save(session: stored)
            return stored
        }
        // Cold-start fallback: return Keychain snapshot (shown while supabase-swift refreshes).
        return KeychainService.loadSession()
    }

    public func currentAccessToken() async -> String? {
        // supabase-swift auto-refreshes the access token when the refresh token is
        // still valid — this is what keeps a session that's been idle for hours
        // working on the next request instead of silently failing with a 401.
        if let session = try? await client.auth.session {
            let stored = StoredSession(
                accessToken: session.accessToken,
                userID:      session.user.id.uuidString,
                email:       session.user.email ?? ""
            )
            KeychainService.save(session: stored)
            return session.accessToken
        }
        // Refresh failed (e.g. transient network blip). Fall back to the last known
        // token so a brief failure doesn't break the request; a definitive 401 from
        // the backend is what triggers sign-out (see AuthStore.expireSession()).
        return KeychainService.loadSession()?.accessToken
    }

    // MARK: - Error mapping

    private func mapError(_ error: Error) -> AuthError {
        let description = error.localizedDescription.lowercased()
        if description.contains("invalid") || description.contains("credentials") ||
           description.contains("password") || description.contains("email") {
            return .invalidCredentials
        }
        if description.contains("network") || description.contains("connection") {
            return .networkError
        }
        return .underlying(error)
    }

    /// Maps sign-up failures. Supabase reports a taken address and a rejected
    /// password as distinct messages — both deserve their own actionable copy
    /// rather than the generic "invalid credentials" used on sign-in.
    private func mapSignUpError(_ error: Error) -> AuthError {
        let description = error.localizedDescription.lowercased()
        if description.contains("already registered") ||
           description.contains("already been registered") ||
           description.contains("already exists") ||
           description.contains("user already") {
            return .emailAlreadyRegistered
        }
        if description.contains("password") &&
           (description.contains("weak") || description.contains("at least") ||
            description.contains("should be") || description.contains("short")) {
            return .weakPassword
        }
        if description.contains("network") || description.contains("connection") {
            return .networkError
        }
        return .underlying(error)
    }
}
