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

    /// A plain-language, low-threshold summary of what this group of markers
    /// tells you about your body — what they do, and why you'd want more or
    /// less of them. Written for non-medical readers; shown at the top of the
    /// per-category view so people understand their results at a glance.
    public var summary: String {
        switch self {
        case .lipids:
            return "These are the fats in your blood. LDL (\u{201C}bad\u{201D}) "
                + "cholesterol and triglycerides can build up inside your "
                + "arteries, so lower is usually better. HDL (\u{201C}good\u{201D}) "
                + "cholesterol helps clear that build-up away, so higher is "
                + "better. Keeping them in balance protects your heart and "
                + "blood vessels over the years."
        case .cbc:
            return "A complete blood count is a snapshot of the cells in your "
                + "blood. Red blood cells and hemoglobin carry oxygen around "
                + "your body — too few can leave you tired and short of breath. "
                + "White blood cells fight infection, and platelets help your "
                + "blood clot. These numbers show how well your body is making "
                + "and maintaining its blood."
        case .metabolic:
            return "This is how your body handles sugar (glucose) for energy. "
                + "Glucose is your blood sugar right now, while HbA1c reflects "
                + "your average over the past three months or so. Steady values "
                + "toward the lower end lower your long-term risk of diabetes "
                + "and help protect your nerves, eyes, and blood vessels."
        case .thyroid:
            return "Your thyroid is a small gland in your neck that sets your "
                + "body's \u{201C}speed\u{201D} — how fast you burn energy. These "
                + "markers show whether it's running too fast or too slow, which "
                + "can affect your weight, mood, energy, and heart rate. The aim "
                + "is to keep them in balance, not too high or too low."
        case .renal:
            return "These show how well your kidneys are filtering waste out of "
                + "your blood. Creatinine is a waste product, and eGFR estimates "
                + "your filtering power — so a higher eGFR and lower creatinine "
                + "generally mean healthier kidneys. Watching the trend helps "
                + "catch any decline early."
        case .liver:
            return "Your liver processes nutrients, filters out toxins, and "
                + "makes important proteins. Enzymes like ALT, AST, GGT, and ALP "
                + "leak into your blood when liver cells are stressed or "
                + "inflamed, so lower levels usually mean a happier liver. "
                + "Bilirubin reflects how well your liver clears the waste from "
                + "old red blood cells."
        case .nutrients:
            return "These are key vitamins and minerals your body needs to run "
                + "well — like iron stores (ferritin), vitamin B12, folate, and "
                + "vitamin D. Running low can leave you tired, weak, or "
                + "run-down, while some can also be too high. The goal is to "
                + "keep your stores in a healthy range so your body has what it "
                + "needs."
        case .electrolytes:
            return "Electrolytes are minerals like sodium, potassium, calcium, "
                + "and magnesium that carry tiny electrical signals through your "
                + "body. They keep your heart beating steadily, your muscles and "
                + "nerves working, and your fluids balanced. Both too high and "
                + "too low can cause trouble, so the sweet spot is the middle."
        case .other:
            return "These are additional measurements from your lab results "
                + "that don't fall into the main groups. Tap any marker to see "
                + "its trend and reference range."
        }
    }
}

// MARK: - Keyword classification (first match wins)

private let categoryRules: [(BiomarkerCategory, [String])] = [
    (.lipids,       ["hdl", "ldl", "kolesterol", "non-hdl", "triglyserid",
                     "apolipoprotein", "apob", "apo-b", "lp(a)", "lipoprotein (a)"]),
    (.thyroid,      ["tsh", "t4", "tyroxin"]),
    (.metabolic,    ["hba1c", "glukose", "urat", "urinsyre", "uric"]),
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
