import Foundation

/// A `Sendable` snapshot of the authenticated session shared app-wide.
/// Deliberately decoupled from `supabase-swift` types so tests and previews
/// can use `MockAuthService` without importing Supabase.
public struct StoredSession: Sendable, Equatable {
    public let accessToken: String
    public let userID: String
    public let email: String

    public init(accessToken: String, userID: String, email: String) {
        self.accessToken = accessToken
        self.userID = userID
        self.email = email
    }
}
