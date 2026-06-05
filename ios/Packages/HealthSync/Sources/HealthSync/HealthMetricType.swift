import Foundation

/// The HealthKit-sourced metrics this app can import.
///
/// Weight and blood pressure map onto existing `body_metrics` columns.
/// The three heart signals (resting HR, HRV, average HR) were added in the
/// heart-metrics sprint and require migration 016_heart_metrics.sql.
public enum HealthMetricType: String, CaseIterable, Sendable, Identifiable {
    case weight
    case bloodPressure
    case restingHeartRate
    case heartRateVariability
    case heartRate

    public var id: String { rawValue }

    /// The metric types imported by default on first connect.
    public static let defaultEnabled: Set<HealthMetricType> = [
        .weight, .bloodPressure, .restingHeartRate, .heartRateVariability, .heartRate
    ]
}
