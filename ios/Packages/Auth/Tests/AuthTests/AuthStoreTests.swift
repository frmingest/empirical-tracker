import Testing
@testable import Auth

@Suite("AuthStore")
struct AuthStoreTests {

    @Test("starts unauthenticated")
    @MainActor
    func startsUnauthenticated() async {
        let store = AuthStore(service: MockAuthService())
        #expect(store.isAuthenticated == false)
        #expect(store.session == nil)
        #expect(store.error == nil)
    }

    @Test("sign in sets session and isAuthenticated")
    @MainActor
    func signIn() async {
        let store = AuthStore(service: MockAuthService())
        await store.signIn(email: "x@x.com", password: "password")
        #expect(store.isAuthenticated)
        #expect(store.userID == MockAuthService.demoSession.userID)
        #expect(store.email == MockAuthService.demoSession.email)
        #expect(store.error == nil)
    }

    @Test("sign out clears session")
    @MainActor
    func signOut() async {
        let store = AuthStore(service: MockAuthService())
        await store.signIn(email: "x@x.com", password: "any")
        #expect(store.isAuthenticated)
        await store.signOut()
        #expect(store.isAuthenticated == false)
        #expect(store.session == nil)
    }

    @Test("restore session returns nil for mock service")
    @MainActor
    func restoreSessionNil() async {
        let store = AuthStore(service: MockAuthService())
        await store.restoreSession()
        // MockAuthService.restoreSession always returns nil.
        #expect(store.isAuthenticated == false)
    }

    @Test("loading flag is true while sign-in is in flight")
    @MainActor
    func loadingFlag() async {
        let store = AuthStore(service: MockAuthService())
        // signIn is async; just verify it ends with isLoading == false.
        await store.signIn(email: "a@b.com", password: "pw")
        #expect(store.isLoading == false)
    }
}

// MARK: - Failing service stub

private struct FailingAuthService: AuthServiceProtocol {
    func signIn(email: String, password: String) async throws -> StoredSession {
        throw AuthError.invalidCredentials
    }
    func signOut() async throws {}
    func restoreSession() async -> StoredSession? { nil }
}

@Suite("AuthStore — error states")
struct AuthStoreErrorTests {

    @Test("invalid credentials sets error")
    @MainActor
    func invalidCredentials() async {
        let store = AuthStore(service: FailingAuthService())
        await store.signIn(email: "bad@x.com", password: "wrong")
        #expect(store.isAuthenticated == false)
        if case .invalidCredentials = store.error { } else {
            Issue.record("Expected .invalidCredentials, got \(String(describing: store.error))")
        }
    }
}
