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
        // Backend sends dates as "YYYY-MM-DD"; use a flexible strategy.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withFullDate, .withDashSeparatorInDate]
        let isoFull = ISO8601DateFormatter()
        isoFull.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        dec.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let str = try container.decode(String.self)
            if let d = iso.date(from: str) ?? isoFull.date(from: str) { return d }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Unrecognised date: \(str)")
        }
        return dec
    }()
}
