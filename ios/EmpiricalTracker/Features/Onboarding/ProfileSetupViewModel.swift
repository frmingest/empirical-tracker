import BodyMetrics
import Foundation
import Observation

/// Drives the first-run profile setup screen (`ProfileSetupView`).
///
/// Responsibilities:
/// - Holds the unit-aware form draft (height / weight / waist, biological sex).
/// - Converts the user's chosen units to the canonical metric values on save.
/// - Persists static attributes (height, sex) to `UserProfileStore`, the chosen
///   unit system to `SettingsStore`, and the time-series measurements (weight,
///   waist) to the `body_metrics` backend as a single dated row.
///
/// Every field is optional — the screen can be skipped entirely — so validation
/// only flags values the user actually typed.
@MainActor
@Observable
final class ProfileSetupViewModel {

    // MARK: - Unit selection

    var units: MeasurementSystem {
        didSet { if oldValue != units { convertDraft(from: oldValue, to: units) } }
    }

    // MARK: - Form draft (strings, so empty == not provided)

    /// Metric height entry (cm).
    var heightCm = ""
    /// Imperial height entry (feet + inches).
    var heightFeet = ""
    var heightInches = ""

    var weight = ""
    var waist = ""

    var biologicalSex: BiologicalSex?

    // MARK: - Save state

    var isSaving = false
    var errorMessage: String?

    // MARK: - Dependencies

    private let profile: UserProfileStore
    private let settings: SettingsStore
    private let bodyMetrics: BodyMetricsRepository

    init(
        profile: UserProfileStore,
        settings: SettingsStore,
        bodyMetrics: BodyMetricsRepository
    ) {
        self.profile = profile
        self.settings = settings
        self.units = settings.measurementSystem
        self.biologicalSex = profile.biologicalSex
        self.bodyMetrics = bodyMetrics

        // Pre-fill height from any previously saved profile value.
        if let cm = profile.heightCm {
            switch units {
            case .metric:
                heightCm = Self.format(cm)
            case .imperial:
                let (ft, inch) = UnitConvert.feetInches(fromCm: cm)
                heightFeet = String(ft)
                heightInches = String(inch)
            }
        }
    }

    // MARK: - Parsed canonical values (nil when blank or invalid)

    /// Height in cm, derived from whichever unit-specific fields are active.
    var heightCmValue: Double? {
        switch units {
        case .metric:
            return Self.parse(heightCm)
        case .imperial:
            let ft = Self.parse(heightFeet) ?? 0
            let inch = Self.parse(heightInches) ?? 0
            guard ft > 0 || inch > 0 else { return nil }
            return UnitConvert.cm(fromFeet: ft, inches: inch)
        }
    }

    /// Weight in kg, converting from pounds when imperial.
    var weightKgValue: Double? {
        guard let raw = Self.parse(weight) else { return nil }
        return units == .metric ? raw : UnitConvert.kg(fromPounds: raw)
    }

    /// Waist in cm, converting from inches when imperial.
    var waistCmValue: Double? {
        guard let raw = Self.parse(waist) else { return nil }
        return units == .metric ? raw : UnitConvert.cm(fromInches: raw)
    }

    // MARK: - Validation

    private var hasHeightInput: Bool {
        switch units {
        case .metric:   return !heightCm.trimmed.isEmpty
        case .imperial: return !heightFeet.trimmed.isEmpty || !heightInches.trimmed.isEmpty
        }
    }

    /// Inline error for an out-of-range / unparseable *typed* value. Blank fields
    /// are never an error — the whole screen is optional.
    var validationError: String? {
        if hasHeightInput {
            guard let cm = heightCmValue, (50...272).contains(cm) else {
                return String(localized: "profile.error.height")
            }
        }
        if !weight.trimmed.isEmpty {
            guard let kg = weightKgValue, (2...500).contains(kg) else {
                return String(localized: "profile.error.weight")
            }
        }
        if !waist.trimmed.isEmpty {
            guard let cm = waistCmValue, (20...300).contains(cm) else {
                return String(localized: "profile.error.waist")
            }
        }
        return nil
    }

    /// True when at least one field is filled and nothing typed is invalid.
    var canSave: Bool {
        let anyInput = hasHeightInput
            || !weight.trimmed.isEmpty
            || !waist.trimmed.isEmpty
            || biologicalSex != nil
        return anyInput && validationError == nil
    }

    // MARK: - Actions

    /// Persists the entered profile, then marks setup complete. Static attributes
    /// (height, sex, units) save locally and never fail; the body-metric write can
    /// fail on the network, in which case we surface the error and keep the user on
    /// the screen so the typed data is not silently lost.
    func save() async {
        guard validationError == nil else { return }
        isSaving = true
        errorMessage = nil

        // Local, always-succeeds writes first.
        settings.measurementSystem = units
        profile.update(heightCm: heightCmValue, biologicalSex: biologicalSex)

        // Time-series measurements go to the backend as one dated row.
        if let payload = bodyMetricPayload() {
            do {
                try await bodyMetrics.create(payload)
            } catch {
                errorMessage = error.localizedDescription
                isSaving = false
                return
            }
        }

        isSaving = false
        profile.markSetupComplete()
    }

    /// Skips setup without persisting anything except the completion flag, so the
    /// screen is not shown again. The user can fill everything in later.
    func skip() {
        profile.markSetupComplete()
    }

    /// Records the unit preference even when the user skips, since they made an
    /// explicit choice on the screen. Called by the skip path before completing.
    func persistUnitsOnly() {
        settings.measurementSystem = units
    }

    // MARK: - Helpers

    /// Builds a `body_metrics` payload for today from any provided weight/waist,
    /// or `nil` when neither was entered.
    private func bodyMetricPayload() -> BodyMetricPayload? {
        guard weightKgValue != nil || waistCmValue != nil else { return nil }
        return BodyMetricPayload(
            measuredOn: Calendar.current.startOfDay(for: .now),
            weightKg: weightKgValue,
            waistCm: waistCmValue,
            note: String(localized: "profile.body_note"),
            source: .manual
        )
    }

    /// Re-expresses the current numeric draft when the user flips the unit toggle so
    /// the typed values are preserved rather than reinterpreted (e.g. 80 kg shown as
    /// ~176 lb, not "80 lb").
    private func convertDraft(from old: MeasurementSystem, to new: MeasurementSystem) {
        guard old != new else { return }

        // Height
        if new == .imperial, let cm = Self.parse(heightCm) {
            let (ft, inch) = UnitConvert.feetInches(fromCm: cm)
            heightFeet = String(ft)
            heightInches = String(inch)
            heightCm = ""
        } else if new == .metric {
            let ft = Self.parse(heightFeet) ?? 0
            let inch = Self.parse(heightInches) ?? 0
            if ft > 0 || inch > 0 {
                heightCm = Self.format(UnitConvert.cm(fromFeet: ft, inches: inch))
            }
            heightFeet = ""
            heightInches = ""
        }

        // Weight
        if let w = Self.parse(weight) {
            weight = new == .imperial
                ? Self.format(UnitConvert.pounds(fromKg: w))
                : Self.format(UnitConvert.kg(fromPounds: w))
        }

        // Waist
        if let wa = Self.parse(waist) {
            waist = new == .imperial
                ? Self.format(UnitConvert.inches(fromCm: wa))
                : Self.format(UnitConvert.cm(fromInches: wa))
        }
    }

    // MARK: - Parsing / formatting (tolerates Norwegian decimal commas)

    private static func parse(_ text: String) -> Double? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        return Double(trimmed.replacingOccurrences(of: ",", with: "."))
    }

    /// One decimal place, trailing `.0` trimmed, locale-neutral.
    private static func format(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespaces) }
}
