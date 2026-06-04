import Foundation

/// The unit system the user prefers for entering and reading body measurements.
///
/// The backend stores body metrics in **metric** canonical units (`weight_kg`,
/// `waist_cm`) and the local profile stores height in **cm**, so this enum is a
/// *presentation* preference: the onboarding form (and any future imperial-aware
/// screen) converts to/from canonical metric at the edge via the helpers below.
///
/// Persisted in `SettingsStore` so it survives relaunch and can be changed later
/// in Settings.
public enum MeasurementSystem: String, CaseIterable, Sendable, Identifiable {
    /// Kilograms + centimetres (the canonical storage units).
    case metric
    /// Pounds + feet/inches.
    case imperial

    public var id: String { rawValue }

    /// Default for a fresh install. Metric matches the backend's storage units and
    /// the app's Norwegian-first audience.
    public static let `default`: MeasurementSystem = .metric

    public var label: String {
        switch self {
        case .metric:   return String(localized: "units.metric")
        case .imperial: return String(localized: "units.imperial")
        }
    }

    // MARK: - Unit symbols (for field suffixes)

    var weightUnit: String {
        switch self {
        case .metric:   return String(localized: "units.kg")
        case .imperial: return String(localized: "units.lb")
        }
    }

    var lengthUnit: String {
        switch self {
        case .metric:   return String(localized: "units.cm")
        case .imperial: return String(localized: "units.in")
        }
    }
}

// MARK: - Conversions

/// Pure, well-tested unit conversions between the user's chosen system and the
/// canonical metric units the backend / profile store persist. Kept free of UI so
/// they can be unit-tested in isolation.
enum UnitConvert {
    static let lbPerKg = 2.2046226218
    static let inPerCm = 0.3937007874
    static let cmPerInch = 2.54
    static let inchesPerFoot = 12.0

    // Weight ---------------------------------------------------------------

    static func kg(fromPounds lb: Double) -> Double { lb / lbPerKg }
    static func pounds(fromKg kg: Double) -> Double { kg * lbPerKg }

    // Waist / single-axis length ------------------------------------------

    static func cm(fromInches inches: Double) -> Double { inches * cmPerInch }
    static func inches(fromCm cm: Double) -> Double { cm * inPerCm }

    // Height (imperial is split feet + inches) -----------------------------

    static func cm(fromFeet feet: Double, inches: Double) -> Double {
        cm(fromInches: feet * inchesPerFoot + inches)
    }

    /// Splits a canonical cm height into whole feet + remaining inches (rounded).
    static func feetInches(fromCm cm: Double) -> (feet: Int, inches: Int) {
        let totalInches = (inches(fromCm: cm)).rounded()
        let feet = Int(totalInches / inchesPerFoot)
        let remainder = Int(totalInches.truncatingRemainder(dividingBy: inchesPerFoot))
        return (feet, remainder)
    }
}
