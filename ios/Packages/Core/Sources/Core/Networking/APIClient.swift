import Foundation

/// Typed async REST client. Thread-safe via Swift actor isolation.
/// Mirrors the 28 endpoints declared in `web/src/lib/api.ts`.
public actor APIClient {

    // MARK: - Configuration

    public struct Configuration: Sendable {
        public let baseURL: URL
        /// Maximum retry attempts for 5xx / network errors.
        public let maxRetries: Int
        /// Initial backoff delay in nanoseconds (doubles on each retry).
        public let initialBackoffNs: UInt64

        public init(
            baseURL: URL,
            maxRetries: Int = 3,
            initialBackoffNs: UInt64 = 300_000_000
        ) {
            self.baseURL = baseURL
            self.maxRetries = maxRetries
            self.initialBackoffNs = initialBackoffNs
        }

        /// Reads `EMPIRICAL_API_URL` from the environment (for CI / Xcode schemes),
        /// falling back to the Railway production URL.
        public static func resolved() -> Configuration {
            let raw = ProcessInfo.processInfo.environment["EMPIRICAL_API_URL"]
                ?? "https://api-production-42c5.up.railway.app"
            let url = URL(string: raw) ?? URL(string: "http://localhost:8000")!
            return Configuration(baseURL: url)
        }
    }

    // MARK: - Properties

    private let config: Configuration
    private let session: URLSession
    private let tokenProvider: any TokenProvider

    // MARK: - Init

    public init(
        config: Configuration = .resolved(),
        tokenProvider: any TokenProvider,
        session: URLSession = .shared
    ) {
        self.config = config
        self.tokenProvider = tokenProvider
        self.session = session
    }

    // MARK: - Public API

    /// Performs a request and decodes the JSON body into `T`.
    public func request<T: Decodable & Sendable>(
        _ endpoint: Endpoint,
        as type: T.Type = T.self
    ) async throws -> T {
        let req = try await buildRequest(for: endpoint)
        return try await perform(req, decoding: type, retriesLeft: config.maxRetries)
    }

    /// Performs a request and discards the response body (DELETE, etc.).
    public func requestEmpty(_ endpoint: Endpoint) async throws {
        let req = try await buildRequest(for: endpoint)
        let (data, response) = try await session.data(for: req)
        try validate(response: response, data: data)
    }

    /// Performs a request and returns the raw, undecoded response body.
    /// Used for binary downloads such as the GDPR export (JSON document or CSV zip).
    public func requestData(_ endpoint: Endpoint) async throws -> Data {
        let req = try await buildRequest(for: endpoint)
        return try await performData(req, retriesLeft: config.maxRetries)
    }

    // MARK: - Private helpers

    private func buildRequest(for endpoint: Endpoint) async throws -> URLRequest {
        var components = URLComponents(
            url: config.baseURL.appendingPathComponent(endpoint.path),
            resolvingAgainstBaseURL: true
        )
        components?.queryItems = endpoint.queryItems

        guard let url = components?.url else { throw APIError.invalidURL }

        var req = URLRequest(url: url, timeoutInterval: 30)
        req.httpMethod = endpoint.method.rawValue
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("EmpiricalTracker-iOS/1.0", forHTTPHeaderField: "User-Agent")

        if let token = await tokenProvider.currentToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let body = endpoint.body {
            req.httpBody = try JSONEncoder.api.encode(body)
        }

        return req
    }

    private func perform<T: Decodable & Sendable>(
        _ req: URLRequest,
        decoding type: T.Type,
        retriesLeft: Int
    ) async throws -> T {
        do {
            let (data, response) = try await session.data(for: req)
            try validate(response: response, data: data)
            do {
                return try JSONDecoder.api.decode(T.self, from: data)
            } catch let e as DecodingError {
                throw APIError.decodingError(e)
            }
        } catch let error as APIError {
            if error.isRetryable && retriesLeft > 0 {
                let delay = config.initialBackoffNs * UInt64(config.maxRetries - retriesLeft + 1)
                try await Task.sleep(nanoseconds: delay)
                return try await perform(req, decoding: type, retriesLeft: retriesLeft - 1)
            }
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func performData(_ req: URLRequest, retriesLeft: Int) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: req)
            try validate(response: response, data: data)
            return data
        } catch let error as APIError {
            if error.isRetryable && retriesLeft > 0 {
                let delay = config.initialBackoffNs * UInt64(config.maxRetries - retriesLeft + 1)
                try await Task.sleep(nanoseconds: delay)
                return try await performData(req, retriesLeft: retriesLeft - 1)
            }
            throw error
        } catch {
            throw APIError.networkError(error)
        }
    }

    private func validate(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }
        switch http.statusCode {
        case 200...299: return
        case 401:       throw APIError.unauthorized
        case 404:       throw APIError.notFound
        default:
            let message = String(data: data, encoding: .utf8)
            throw APIError.serverError(statusCode: http.statusCode, message: message)
        }
    }
}

// MARK: - Encoder / Decoder

extension JSONEncoder {
    public static let api: JSONEncoder = {
        let enc = JSONEncoder()
        enc.keyEncodingStrategy = .convertToSnakeCase
        enc.dateEncodingStrategy = .iso8601
        return enc
    }()
}

extension JSONDecoder {
    public static let api: JSONDecoder = {
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        // Backend dates arrive in three shapes:
        //   • date only           — "2026-06-04"               (logged_on, created_on…)
        //   • ISO datetime        — "2026-06-04T08:15:30+00:00" (no fractional seconds)
        //   • ISO datetime + frac — "2026-06-04T08:15:30.123456Z"
        // The last is what Postgres `timestamptz` returns through PostgREST: up to six
        // fractional digits. ISO8601DateFormatter only reliably parses three, so a
        // microsecond `created_at` (e.g. on a freshly inserted custom_foods row) would
        // otherwise fail to decode and turn a *successful* write into a thrown error.
        // We therefore strip an arbitrary-length fractional component as a final fallback.
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let isoFractional = ISO8601DateFormatter()
        isoFractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let isoPlain = ISO8601DateFormatter()
        isoPlain.formatOptions = [.withInternetDateTime]
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = dateOnly.date(from: str)
                ?? isoFractional.date(from: str)
                ?? isoPlain.date(from: str) {
                return d
            }
            // Strip fractional seconds of any length (".123456") and retry — sub-second
            // precision is irrelevant for the dates this client decodes.
            let stripped = str.replacingOccurrences(
                of: #"\.\d+"#, with: "", options: .regularExpression
            )
            if let d = isoPlain.date(from: stripped) { return d }
            throw DecodingError.dataCorruptedError(
                in: container, debugDescription: "Unrecognised date: \(str)"
            )
        }
        return dec
    }()
}
