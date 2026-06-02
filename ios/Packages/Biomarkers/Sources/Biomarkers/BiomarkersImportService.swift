import Core
import Foundation

/// Handles `POST /biomarkers/import` as a multipart/form-data upload.
///
/// `APIClient` is designed for JSON. File upload requires a different
/// URLRequest shape (multipart body), so this service builds the request
/// directly while still borrowing the base URL and auth token from the
/// shared `APIClient` configuration.
public struct BiomarkersImportService: Sendable {

    private let baseURL: URL
    private let tokenProvider: any TokenProvider

    public init(baseURL: URL, tokenProvider: any TokenProvider) {
        self.baseURL = baseURL
        self.tokenProvider = tokenProvider
    }

    // MARK: - Upload

    /// Uploads the file at `fileURL` to `POST /biomarkers/import`.
    ///
    /// Progress is reported via `onProgress` (0.0 → 1.0) on the calling actor.
    /// The caller is responsible for security-scoped access (`startAccessingSecurityScopedResource`).
    public func upload(
        fileURL: URL,
        onProgress: @Sendable @escaping (Double) -> Void
    ) async throws -> ImportResult {
        let url = baseURL.appendingPathComponent("/biomarkers/import")
        let token = await tokenProvider.currentToken()

        let boundary = "EmpiricalBoundary-\(UUID().uuidString)"
        var request = URLRequest(url: url, timeoutInterval: 120)
        request.httpMethod = "POST"
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        request.setValue("EmpiricalTracker-iOS/1.0", forHTTPHeaderField: "User-Agent")
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let fileData = try Data(contentsOf: fileURL)
        let fileName = fileURL.lastPathComponent
        let body = buildMultipartBody(
            data: fileData,
            fileName: fileName,
            fieldName: "file",
            mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            boundary: boundary
        )
        request.httpBody = body
        request.setValue("\(body.count)", forHTTPHeaderField: "Content-Length")

        // URLSession delegate-based upload so we can stream progress.
        let delegate = UploadDelegate(onProgress: onProgress)
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)

        let (data, response) = try await session.data(for: request)
        session.invalidateAndCancel()

        guard let http = response as? HTTPURLResponse else {
            throw APIError.invalidResponse
        }

        if http.statusCode == 401 { throw APIError.unauthorized }
        if http.statusCode == 404 { throw APIError.notFound }

        guard (200...299).contains(http.statusCode) else {
            // Try to surface a server-side error message.
            let message = (try? JSONDecoder.api.decode(ImportErrorResponse.self, from: data))?.detail
                ?? String(data: data, encoding: .utf8)
            throw APIError.serverError(statusCode: http.statusCode, message: message)
        }

        do {
            return try JSONDecoder.api.decode(ImportResult.self, from: data)
        } catch let e as DecodingError {
            throw APIError.decodingError(e)
        }
    }

    // MARK: - Multipart helpers

    private func buildMultipartBody(
        data: Data,
        fileName: String,
        fieldName: String,
        mimeType: String,
        boundary: String
    ) -> Data {
        var body = Data()
        let crlf = "\r\n"
        body.appendString("--\(boundary)\(crlf)")
        body.appendString("Content-Disposition: form-data; name=\"\(fieldName)\"; filename=\"\(fileName)\"\(crlf)")
        body.appendString("Content-Type: \(mimeType)\(crlf)\(crlf)")
        body.append(data)
        body.appendString("\(crlf)--\(boundary)--\(crlf)")
        return body
    }
}

// MARK: - Upload progress delegate

private final class UploadDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    private let onProgress: @Sendable (Double) -> Void

    init(onProgress: @Sendable @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didSendBodyData bytesSent: Int64,
        totalBytesSent: Int64,
        totalBytesExpectedToSend: Int64
    ) {
        guard totalBytesExpectedToSend > 0 else { return }
        let fraction = Double(totalBytesSent) / Double(totalBytesExpectedToSend)
        onProgress(fraction)
    }
}

// MARK: - Data helper

private extension Data {
    mutating func appendString(_ string: String) {
        if let d = string.data(using: .utf8) { append(d) }
    }
}
