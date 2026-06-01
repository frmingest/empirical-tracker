import Foundation

// MARK: - DietEvent

/// An annotated life-event that can be overlaid on biomarker charts.
/// Mirrors `DietEvent` in `web/src/lib/api.ts`.
public struct DietEvent: Codable, Identifiable, Sendable {
    public let id: String
    public let label: String
    public let kind: Kind
    /// First day of the event. Also serves as the single-date marker if `endedOn` is nil.
    public let startedOn: Date
    /// If set, the event spans a period [startedOn, endedOn].
    public let endedOn: Date?
    public let note: String?

    public enum Kind: String, Codable, CaseIterable, Sendable {
        case diet
        case fast
        case supplement
        case medication
        case lifestyle
        case other

        public var icon: String {
            switch self {
            case .diet:       return "fork.knife"
            case .fast:       return "timer"
            case .supplement: return "pill"
            case .medication: return "cross.case"
            case .lifestyle:  return "figure.walk"
            case .other:      return "ellipsis.circle"
            }
        }
    }

    /// True when the event spans a date range rather than a single point.
    public var isPeriod: Bool { endedOn != nil }
}

// MARK: - DietEventPayload (POST body)

public struct DietEventPayload: Encodable, Sendable {
    public let label: String
    public let kind: DietEvent.Kind
    public let startedOn: Date
    public let endedOn: Date?
    public let note: String?

    public init(
        label: String,
        kind: DietEvent.Kind,
        startedOn: Date,
        endedOn: Date? = nil,
        note: String? = nil
    ) {
        self.label = label
        self.kind = kind
        self.startedOn = startedOn
        self.endedOn = endedOn
        self.note = note
    }
}

// MARK: - DietFocus

/// Mirrors the `DietKey` union type and `UserSettings.diet` field.
public enum DietFocus: String, Codable, CaseIterable, Identifiable, Sendable {
    case all
    case carnivore
    case lowCarb = "low_carb"
    case fasting
    case custom

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .all:       return "All"
        case .carnivore: return "Carnivore"
        case .lowCarb:   return "Low-carb"
        case .fasting:   return "Fasting"
        case .custom:    return "Custom"
        }
    }

    /// Marker names (name_no) shown for this focus, mirroring `dietProfiles.ts`.
    /// The full set is maintained in `DietProfiles` — here we keep names as strings
    /// so the Core package stays decoupled from per-biomarker business logic.
    public static let markerSets: [DietFocus: Set<String>] = [
        .carnivore: [
            "Kolesterol", "HDL-kolesterol", "LDL-kolesterol", "Non-HDL kolesterol",
            "Triglyserider", "HbA1c",
            "ALT", "GGT",
            "Kreatinin", "eGFR",
            "Ferritin", "Jern", "Transferrin",
            "B12", "Aktivt B12", "Folat", "Homocystein",
            "Vitamin D",
            "Natrium", "Kalium",
            "Hemoglobin", "Hematokrit",
        ],
        .lowCarb: [
            "HbA1c",
            "Kolesterol", "HDL-kolesterol", "LDL-kolesterol", "Non-HDL kolesterol", "Triglyserider",
            "ALT", "GGT",
            "Natrium", "Kalium",
            "Ferritin", "Jern",
        ],
        .fasting: [
            "Natrium", "Kalium",
            "HbA1c",
            "ALT", "GGT",
            "Kreatinin", "eGFR",
            "Hemoglobin", "Leukocytter",
            "Kolesterol", "LDL-kolesterol", "Triglyserider",
        ],
    ]
}
