import Foundation

public enum APIError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case unauthorized
    case notFound
    case serverError(statusCode: Int, message: String?)
    case decodingError(DecodingError)
    case networkError(any Error)

    public var errorDescription: String? {
        switch self {
        case .invalidURL:           return "Invalid request URL."
        case .invalidResponse:      return "Unexpected server response."
        case .unauthorized:         return "Session expired — please sign in again."
        case .notFound:             return "Requested resource not found."
        case .serverError(let s, let m): return m ?? "Server error (\(s))."
        case .decodingError(let e): return "Data format error: \(e.localizedDescription)"
        case .networkError(let e):  return e.localizedDescription
        }
    }

    /// True if retrying the same request after a short delay is sensible.
    public var isRetryable: Bool {
        switch self {
        case .serverError(let s, _): return s >= 500
        case .networkError:          return true
        default:                     return false
        }
    }

    /// True if this wraps a cancelled task (e.g. SwiftUI tore down the `.task`
    /// because the view disappeared mid-request). Not a real failure — callers
    /// should typically swallow it rather than surface an alert.
    public var isCancellation: Bool {
        guard case .networkError(let e) = self else { return false }
        return e is CancellationError || (e as? URLError)?.code == .cancelled
    }
}
