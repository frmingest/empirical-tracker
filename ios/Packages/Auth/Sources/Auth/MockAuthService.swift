import Foundation

/// Demo-mode `AuthServiceProtocol` — accepts any credentials and returns a hardcoded session.
/// Injected when the Xcode scheme sets `DEMO_MODE=1`, or used in SwiftUI previews and unit tests.
/// Never ships as the production auth provider.
public struct MockAuthService: AuthServiceProtocol {

    public static let demoSession = StoredSession(
        accessToken: "demo-access-token",
        userID:      "00000000-0000-0000-0000-000000000001",
        email:       "demo@empirical.app"
    )

    public init() {}

    public func signIn(email: String, password: String) async throws -> StoredSession {
        // Simulate realistic network latency so the loading indicator renders.
        try await Task.sleep(nanoseconds: 700_000_000)
        return MockAuthService.demoSession
    }

    public func signOut() async throws {
        try await Task.sleep(nanoseconds: 150_000_000)
    }

    /// Demo mode always starts signed out so the login screen is visible on first launch.
    public func restoreSession() async -> StoredSession? { nil }
}
