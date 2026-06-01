import Foundation

public enum HTTPMethod: String, Sendable {
    case get    = "GET"
    case post   = "POST"
    case put    = "PUT"
    case patch  = "PATCH"
    case delete = "DELETE"
}

/// Describes a single API call. Pass an `AnyEncodable` body for POST/PUT/PATCH.
public struct Endpoint: Sendable {
    public let method: HTTPMethod
    public let path: String
    public let queryItems: [URLQueryItem]?
    public let body: (any Encodable & Sendable)?

    public init(
        method: HTTPMethod = .get,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        body: (any Encodable & Sendable)? = nil
    ) {
        self.method = method
        self.path = path
        self.queryItems = queryItems
        self.body = body
    }

    // MARK: - Convenience factories

    public static func get(_ path: String, query: [URLQueryItem]? = nil) -> Self {
        Endpoint(method: .get, path: path, queryItems: query)
    }

    public static func post<B: Encodable & Sendable>(_ path: String, body: B) -> Self {
        Endpoint(method: .post, path: path, body: body)
    }

    public static func put<B: Encodable & Sendable>(_ path: String, body: B) -> Self {
        Endpoint(method: .put, path: path, body: body)
    }

    public static func delete(_ path: String) -> Self {
        Endpoint(method: .delete, path: path)
    }
}
