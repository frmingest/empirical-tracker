import Core
import Foundation

// MARK: - Canonical marker keys

/// Stable canonical identifier for each biomarker in the panel.
/// Mirrors `MarkerKey` in `web/src/lib/dietProfiles.ts`.
public enum MarkerKey: String, CaseIterable, Sendable {
    case hdl, ldl, totalChol, nonHdl
    case hemoglobin, rbc, wbc, hematocrit, mch, mchc, mcv
    case hba1c, tsh, freeT4, creatinine, egfr, alt, ggt
    case ferritin, folate, b12, activeB12, vitaminD, transferrin
    case iron, homocysteine, mma, sodium, potassium
}

// MARK: - Keyword rules (order matters — first match wins)

/// Matches Norwegian lab names to canonical keys with keyword rules.
/// Ordered to resolve ambiguity:
///   hba1c before hemoglobin; non-hdl before hdl; mchc before mch; gfr before kreatinin.
private let markerRules: [(MarkerKey, [String])] = [
    (.hba1c,        ["hba1c"]),
    (.nonHdl,       ["non-hdl"]),
    (.hdl,          ["hdl"]),
    (.ldl,          ["ldl"]),
    (.totalChol,    ["kolesterol", "cholesterol"]),
    (.mchc,         ["mchc"]),
    (.mch,          ["mch"]),
    (.mcv,          ["mcv"]),
    (.hemoglobin,   ["hemoglobin"]),
    (.rbc,          ["erytrocytter"]),
    (.wbc,          ["leukocytter"]),
    (.hematocrit,   ["hematokritt"]),
    (.tsh,          ["tsh"]),
    (.freeT4,       ["t4"]),
    (.egfr,         ["gfr"]),
    (.creatinine,   ["kreatinin"]),
    (.alt,          ["alat"]),
    (.ggt,          ["p-gt", "ggt"]),
    (.ferritin,     ["ferritin"]),
    (.folate,       ["folat"]),
    (.activeB12,    ["aktivt"]),
    (.b12,          ["b12"]),
    (.vitaminD,     ["vitamin d", "25-oh"]),
    (.transferrin,  ["transferrin"]),
    (.iron,         ["jern"]),
    (.homocysteine, ["homocystein"]),
    (.mma,          ["mma", "metylmalon"]),
    (.sodium,       ["natrium"]),
    (.potassium,    ["kalium"]),
]

/// Resolve a Norwegian biomarker name to its canonical key, or nil if unrecognised.
public func markerKey(for nameNo: String) -> MarkerKey? {
    let lower = nameNo.lowercased()
    for (key, keywords) in markerRules {
        if keywords.contains(where: { lower.contains($0) }) { return key }
    }
    return nil
}

// MARK: - Diet marker sets

private let carnivoreKeys: Set<MarkerKey> = [
    .hdl, .ldl, .totalChol, .nonHdl,
    .hba1c,
    .alt, .ggt,
    .creatinine, .egfr,
    .ferritin, .iron, .transferrin,
    .b12, .activeB12, .mma, .homocysteine, .folate,
    .vitaminD,
    .sodium, .potassium,
    .hemoglobin, .hematocrit,
]

private let lowCarbKeys: Set<MarkerKey> = [
    .hba1c,
    .hdl, .ldl, .totalChol, .nonHdl,
    .alt, .ggt,
    .sodium, .potassium,
    .ferritin,
]

private let fastingKeys: Set<MarkerKey> = [
    .sodium, .potassium,
    .hba1c,
    .alt, .ggt,
    .creatinine, .egfr,
    .hemoglobin, .hematocrit,
    .hdl, .ldl, .totalChol, .nonHdl,
]

private let dietKeyMap: [DietFocus: Set<MarkerKey>] = [
    .carnivore: carnivoreKeys,
    .lowCarb:   lowCarbKeys,
    .fasting:   fastingKeys,
]

// MARK: - Public filtering API

/// Whether a single biomarker should be shown for the given diet focus.
public func isDietRelevant(
    _ nameNo: String,
    diet: DietFocus,
    customMarkers: Set<String>
) -> Bool {
    switch diet {
    case .all:    return true
    case .custom: return customMarkers.contains(nameNo)
    default:
        guard let keys = dietKeyMap[diet], let key = markerKey(for: nameNo) else { return false }
        return keys.contains(key)
    }
}

/// Filter a results list to only the markers visible for the given diet focus.
public func filterByDiet(
    _ results: [BiomarkerWithSeries],
    diet: DietFocus,
    customMarkers: Set<String>
) -> [BiomarkerWithSeries] {
    if diet == .all { return results }
    return results.filter { isDietRelevant($0.biomarker.nameNo, diet: diet, customMarkers: customMarkers) }
}

// MARK: - DietOption metadata (mirrors DIET_OPTIONS in dietProfiles.ts)

public struct DietOption: Identifiable, Sendable {
    public let key: DietFocus
    public let label: String
    public let description: String
    public var id: String { key.rawValue }
}

public let dietOptions: [DietOption] = [
    DietOption(
        key: .all,
        label: "All",
        description: "Show every biomarker in your panel."
    ),
    DietOption(
        key: .carnivore,
        label: "Carnivore",
        description: "Lipid response, iron stores, kidney load, liver enzymes, electrolytes and B-vitamin / folate status — the markers most affected by an all-meat diet."
    ),
    DietOption(
        key: .lowCarb,
        label: "Low carb",
        description: "Glycemic control (HbA1c), the full lipid panel, liver enzymes and the electrolytes that shift when you cut carbs."
    ),
    DietOption(
        key: .fasting,
        label: "Fasting",
        description: "Electrolytes, glucose control, kidney and liver markers, plus hydration-sensitive blood counts to watch during a fast."
    ),
    DietOption(
        key: .custom,
        label: "Custom",
        description: "Hand-pick exactly which biomarkers you want to follow."
    ),
]
