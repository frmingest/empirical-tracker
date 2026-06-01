import Foundation

/// Supplies the current bearer token for authenticated API requests.
/// Conformers are responsible for token refresh; a nil return means unauthenticated.
public protocol TokenProvider: Sendable {
    func currentToken() async -> String?
}

/// No-op provider used in previews and unauthenticated contexts.
public struct AnonymousTokenProvider: TokenProvider {
    public init() {}
    public func currentToken() async -> String? { nil }
}
