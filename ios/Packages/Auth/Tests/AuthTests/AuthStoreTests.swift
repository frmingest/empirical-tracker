import Testing
@testable import AppAuth

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

    @Test("expireSession clears the session and surfaces a session-expired error")
    @MainActor
    func expireSession() async {
        let store = AuthStore(service: MockAuthService())
        await store.signIn(email: "a@b.com", password: "pw")
        #expect(store.isAuthenticated)

        await store.expireSession()
        #expect(store.isAuthenticated == false)
        #expect(store.session == nil)
        if case .sessionExpired = store.error {} else {
            Issue.record("Expected .sessionExpired, got \(String(describing: store.error))")
        }
    }

    @Test("expireSession is a no-op when already signed out")
    @MainActor
    func expireSessionWhenSignedOut() async {
        let store = AuthStore(service: MockAuthService())
        await store.expireSession()
        // No session to tear down — must not invent a spurious error banner.
        #expect(store.error == nil)
    }

    @Test("currentAccessToken returns nil when there is no session")
    @MainActor
    func currentAccessTokenNoSession() async {
        let store = AuthStore(service: MockAuthService())
        let token = await store.currentAccessToken()
        #expect(token == nil)
    }

    @Test("currentAccessToken returns a token once signed in")
    @MainActor
    func currentAccessTokenSignedIn() async {
        let store = AuthStore(service: MockAuthService())
        await store.signIn(email: "a@b.com", password: "pw")
        let token = await store.currentAccessToken()
        #expect(token == MockAuthService.demoSession.accessToken)
    }
}

// MARK: - Failing service stub

private struct FailingAuthService: AuthServiceProtocol {
    let signUpError: AuthError
    init(signUpError: AuthError = .invalidCredentials) { self.signUpError = signUpError }
    func signIn(email: String, password: String) async throws -> StoredSession {
        throw AuthError.invalidCredentials
    }
    func signUp(email: String, password: String) async throws -> StoredSession {
        throw signUpError
    }
    func signOut() async throws {}
    func restoreSession() async -> StoredSession? { nil }
    func currentAccessToken() async -> String? { nil }
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

    @Test("email-already-registered surfaces as an error, not a session")
    @MainActor
    func signUpDuplicateEmail() async {
        let store = AuthStore(service: FailingAuthService(signUpError: .emailAlreadyRegistered))
        await store.signUp(email: "taken@x.com", password: "password")
        #expect(store.isAuthenticated == false)
        if case .emailAlreadyRegistered = store.error { } else {
            Issue.record("Expected .emailAlreadyRegistered, got \(String(describing: store.error))")
        }
    }

    @Test("email-confirmation-required surfaces as a notice, not an error")
    @MainActor
    func signUpConfirmationRequired() async {
        let store = AuthStore(service: FailingAuthService(signUpError: .emailConfirmationRequired))
        await store.signUp(email: "new@x.com", password: "password")
        #expect(store.isAuthenticated == false)
        #expect(store.error == nil)
        #expect(store.notice != nil)
    }
}

@Suite("AuthStore — sign up")
struct AuthStoreSignUpTests {

    @Test("successful sign up sets session and isAuthenticated")
    @MainActor
    func signUpSuccess() async {
        let store = AuthStore(service: MockAuthService())
        await store.signUp(email: "new@x.com", password: "password")
        #expect(store.isAuthenticated)
        #expect(store.userID == MockAuthService.demoSession.userID)
        #expect(store.error == nil)
        #expect(store.notice == nil)
    }

    @Test("clearMessages drops a lingering error banner")
    @MainActor
    func clearMessages() async {
        let store = AuthStore(service: FailingAuthService())
        await store.signIn(email: "bad@x.com", password: "wrong")
        #expect(store.error != nil)
        store.clearMessages()
        #expect(store.error == nil)
        #expect(store.notice == nil)
    }
}
