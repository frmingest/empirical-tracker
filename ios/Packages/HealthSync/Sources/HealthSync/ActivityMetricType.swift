import Foundation

/// The HealthKit activity signals this app can import (ADR-033).
///
/// Each type maps to a daily cumulative sum computed inside HealthKit via
/// `HKStatisticsCollectionQuery`, keeping raw-sample volume off the wire.
/// All three are available from iPhone alone — no Apple Watch required.
public enum ActivityMetricType: String, CaseIterable, Sendable, Identifiable {
    case steps
    case activeEnergy
    case exerciseMinutes

    public var id: String { rawValue }

    public static let defaultEnabled: Set<ActivityMetricType> = [
        .steps, .activeEnergy, .exerciseMinutes
    ]
}
