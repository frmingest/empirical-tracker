import Foundation

// Models for the multi-format lab document import (ADR-032 Phase 1).
//
// Unlike the .xlsx path (`ImportModels.swift`), a PDF/photo import is
// probabilistic and medical, so the server never auto-writes it. It returns a
// *candidate* the user reviews and edits, then explicitly applies. These types
// mirror the `/biomarkers/import/document`, `/imports/{id}/apply` shapes.
//
// `testedAt` is kept as a plain "YYYY-MM-DD" string (not `Date`) because it is
// optional in a candidate — the extractor may not find a date, and the user
// fills it in during review before applying.

// MARK: - Candidate (server → app)

/// Response from `POST /biomarkers/import/document`: a staged, reviewable
/// extraction. `importId` identifies the `lab_imports` row to later apply.
public struct LabImportCandidate: Decodable, Sendable {
    public let importId: String
    public let status: String
    public let panels: [LabImportPanel]

    public init(importId: String, status: String, panels: [LabImportPanel]) {
        self.importId = importId
        self.status = status
        self.panels = panels
    }
}

// MARK: - Panel + result (both directions)

/// One blood-draw session in a candidate. `testedAt` is nil when the extractor
/// could not read a date; the review UI requires the user to set one before apply.
public struct LabImportPanel: Codable, Identifiable, Sendable {
    public let id: UUID
    public var testedAt: String?
    public var results: [LabImportResult]

    public init(id: UUID = UUID(), testedAt: String?, results: [LabImportResult]) {
        self.id = id
        self.testedAt = testedAt
        self.results = results
    }

    private enum CodingKeys: String, CodingKey { case testedAt, results }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        testedAt = try c.decodeIfPresent(String.self, forKey: .testedAt)
        results = try c.decodeIfPresent([LabImportResult].self, forKey: .results) ?? []
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(testedAt, forKey: .testedAt)
        try c.encode(results, forKey: .results)
    }
}

/// One extracted analyte. A result is either numeric (`value`) or qualitative
/// (`valueText`). `include` is a client-only flag driving the review checkbox —
/// excluded rows are dropped before the apply payload is built.
public struct LabImportResult: Codable, Identifiable, Sendable {
    public let id: UUID
    public var nameNo: String
    public var value: Double?
    public var valueText: String?
    public var unit: String?
    public var refRangeRaw: String?
    public var include: Bool

    public init(
        id: UUID = UUID(),
        nameNo: String,
        value: Double? = nil,
        valueText: String? = nil,
        unit: String? = nil,
        refRangeRaw: String? = nil,
        include: Bool = true
    ) {
        self.id = id
        self.nameNo = nameNo
        self.value = value
        self.valueText = valueText
        self.unit = unit
        self.refRangeRaw = refRangeRaw
        self.include = include
    }

    private enum CodingKeys: String, CodingKey {
        case nameNo, value, valueText, unit, refRangeRaw
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = UUID()
        nameNo = try c.decode(String.self, forKey: .nameNo)
        value = try c.decodeIfPresent(Double.self, forKey: .value)
        valueText = try c.decodeIfPresent(String.self, forKey: .valueText)
        unit = try c.decodeIfPresent(String.self, forKey: .unit)
        refRangeRaw = try c.decodeIfPresent(String.self, forKey: .refRangeRaw)
        include = true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(nameNo, forKey: .nameNo)
        try c.encodeIfPresent(value, forKey: .value)
        try c.encodeIfPresent(valueText, forKey: .valueText)
        try c.encodeIfPresent(unit, forKey: .unit)
        try c.encodeIfPresent(refRangeRaw, forKey: .refRangeRaw)
    }
}

// MARK: - Request bodies (app → server)

/// Body for `POST /biomarkers/import/document`.
public struct LabDocumentPayload: Encodable, Sendable {
    public let text: String
    public let sourceKind: String  // "text" | "pdf" | "image"

    public init(text: String, sourceKind: String = "text") {
        self.text = text
        self.sourceKind = sourceKind
    }
}

/// Body for `POST /biomarkers/imports/{id}/apply`.
public struct ApplyLabImportPayload: Encodable, Sendable {
    public let panels: [LabImportPanel]
    public init(panels: [LabImportPanel]) { self.panels = panels }
}

/// Response from a successful apply.
public struct LabImportApplyResult: Decodable, Sendable {
    public let panelsApplied: Int
    public let resultsInserted: Int

    public init(panelsApplied: Int, resultsInserted: Int) {
        self.panelsApplied = panelsApplied
        self.resultsInserted = resultsInserted
    }
}
