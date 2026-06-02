import Foundation

/// The HealthKit-sourced metrics this app can import in Sprint 9.
///
/// Deliberately limited to the two signals that map onto the **existing**
/// `body_metrics` columns (`weight_kg`, `systolic`/`diastolic`). Body-composition
/// signals (body-fat %, lean mass, resting HR) require the `withings_measures`
/// table from the migration plan §4.3 and are therefore deferred to the Sprint 10
/// backend work — we request authorization only for what we can actually store, so
/// the App Review usage strings stay honest.
public enum HealthMetricType: String, CaseIterable, Sendable, Identifiable {
    case weight
    case bloodPressure

    public var id: String { rawValue }

    /// The metric types imported by default on first connect.
    public static let defaultEnabled: Set<HealthMetricType> = [.weight, .bloodPressure]
}
