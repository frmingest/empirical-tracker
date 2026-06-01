import Core
import Foundation

// MARK: - Category enum

/// Clinical groupings for the dashboard grid.
/// Mirrors `CATEGORY_ORDER` in `web/src/lib/biomarkerCategories.ts`.
public enum BiomarkerCategory: String, CaseIterable, Identifiable, Sendable {
    case lipids       = "Lipids"
    case cbc          = "CBC"
    case metabolic    = "Metabolic"
    case thyroid      = "Thyroid"
    case renal        = "Renal"
    case liver        = "Liver"
    case nutrients    = "Nutrients"
    case electrolytes = "Electrolytes"
    case other        = "Other"

    public var id: String { rawValue }
    public var displayName: String { rawValue }
}

// MARK: - Keyword classification (first match wins)

private let categoryRules: [(BiomarkerCategory, [String])] = [
    (.lipids,       ["hdl", "ldl", "kolesterol", "non-hdl", "triglyserid"]),
    (.thyroid,      ["tsh", "t4", "tyroxin"]),
    (.metabolic,    ["hba1c", "glukose"]),
    (.cbc,          ["hemoglobin", "erytrocytter", "leukocytter", "hematokritt", "mch", "mcv", "mchc", "trombocytter"]),
    (.renal,        ["kreatinin", "gfr", "nyre"]),
    (.liver,        ["alat", "asat", "p-gt", "ggt", "bilirubin", "alp"]),
    (.nutrients,    ["ferritin", "folat", "b12", "vitamin d", "25-oh", "transferrin", "jern", "tibc", "mma", "homocystein", "aktivt"]),
    (.electrolytes, ["natrium", "kalium", "kalsium", "magnesium", "fosfat"]),
]

/// Classify a biomarker by its Norwegian lab name.
public func biomarkerCategory(for nameNo: String) -> BiomarkerCategory {
    let lower = nameNo.lowercased()
    for (category, keywords) in categoryRules {
        if keywords.contains(where: { lower.contains($0) }) { return category }
    }
    return .other
}

// MARK: - Grouped output

/// A category bucket used by the dashboard grid.
public struct BiomarkerGroup: Identifiable, Sendable {
    public let category: BiomarkerCategory
    public let items: [BiomarkerWithSeries]
    public var id: String { category.rawValue }
}

/// Groups results into ordered category buckets, omitting empty ones.
public func groupedByCategory(_ items: [BiomarkerWithSeries]) -> [BiomarkerGroup] {
    var buckets: [BiomarkerCategory: [BiomarkerWithSeries]] = Dictionary(
        uniqueKeysWithValues: BiomarkerCategory.allCases.map { ($0, []) }
    )
    for item in items {
        let cat = biomarkerCategory(for: item.biomarker.nameNo)
        buckets[cat, default: []].append(item)
    }
    return BiomarkerCategory.allCases.compactMap { cat in
        let group = buckets[cat, default: []]
        return group.isEmpty ? nil : BiomarkerGroup(category: cat, items: group)
    }
}

// MARK: - Display utilities

/// Strip Norwegian parenthetical suffixes; truncate to 26 chars.
/// Mirrors `shortLabel()` in `biomarkerCategories.ts`.
public func shortBiomarkerLabel(_ name: String) -> String {
    let noParens = name
        .replacingOccurrences(of: #"\s*\([^)]*\)"#, with: "", options: .regularExpression)
        .trimmingCharacters(in: .whitespaces)
    return noParens.count > 26 ? String(noParens.prefix(24)) + "…" : noParens
}

/// Date → "Sep '23" (short axis label).
public func fmtDateShort(_ date: Date) -> String {
    shortDateFormatter.string(from: date)
}

/// Date → "May 22, 2026" (full tooltip label).
public func fmtDateLong(_ date: Date) -> String {
    longDateFormatter.string(from: date)
}

private let shortDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateFormat = "MMM ''yy"
    f.locale = Locale(identifier: "en_US")
    return f
}()

private let longDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .long
    f.locale = Locale(identifier: "en_US")
    return f
}()
