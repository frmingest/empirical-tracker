import Foundation

// MARK: - ImportResult

/// Response body from `POST /biomarkers/import`.
/// The server parses the .xlsx, creates panels, inserts results, and
/// returns a summary so the UI can show the user what happened.
public struct ImportResult: Codable, Equatable, Sendable {
    /// UUID of the panel that was created (one per uploaded file).
    public let panelId: String?
    /// Number of distinct blood-draw sessions created.
    public let panelsCreated: Int
    /// Number of individual biomarker measurements inserted.
    public let resultsInserted: Int
    /// Rows that were present in the file but skipped (unrecognised names, etc.).
    public let skippedRows: Int
    /// Human-readable error strings for rows the server could not parse.
    public let errors: [String]

    public init(
        panelId: String? = nil,
        panelsCreated: Int,
        resultsInserted: Int,
        skippedRows: Int = 0,
        errors: [String] = []
    ) {
        self.panelId = panelId
        self.panelsCreated = panelsCreated
        self.resultsInserted = resultsInserted
        self.skippedRows = skippedRows
        self.errors = errors
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        panelId = try container.decodeIfPresent(String.self, forKey: .panelId)
        panelsCreated = try container.decode(Int.self, forKey: .panelsCreated)
        resultsInserted = try container.decode(Int.self, forKey: .resultsInserted)
        skippedRows = try container.decodeIfPresent(Int.self, forKey: .skippedRows) ?? 0
        errors = try container.decodeIfPresent([String].self, forKey: .errors) ?? []
    }
}

// MARK: - ImportError

/// Structured import failure returned when the server rejects the whole file
/// (wrong format, auth failure, etc.) rather than per-row errors.
public struct ImportErrorResponse: Codable, Sendable {
    public let detail: String
}
