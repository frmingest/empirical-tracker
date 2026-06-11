import Core
import Foundation

/// One day's activity data, ready to POST to `/activity-metrics/batch`.
public struct ActivityMetricPayload: Encodable, Sendable {
    public let measuredOn: Date
    public let steps: Int?
    public let activeEnergyKcal: Double?
    public let exerciseMinutes: Int?
    public let source: String

    public init(
        measuredOn: Date,
        steps: Int? = nil,
        activeEnergyKcal: Double? = nil,
        exerciseMinutes: Int? = nil,
        source: String = "healthkit"
    ) {
        self.measuredOn = measuredOn
        self.steps = steps
        self.activeEnergyKcal = activeEnergyKcal
        self.exerciseMinutes = exerciseMinutes
        self.source = source
    }

    // Snake-case keys to match the backend schema.
    enum CodingKeys: String, CodingKey {
        case measuredOn = "measured_on"
        case steps
        case activeEnergyKcal = "active_energy_kcal"
        case exerciseMinutes = "exercise_minutes"
        case source
    }

    /// `measured_on` is the user's *local* calendar day: `measuredOn` is local
    /// midnight (`Calendar.current.startOfDay`), so it must be formatted in the
    /// current time zone. A UTC formatter shifts it to the previous day for every
    /// positive-offset user (00:00 CEST = 22:00Z the day before). See `CalendarDate`.
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(CalendarDate.string(from: measuredOn), forKey: .measuredOn)
        try c.encodeIfPresent(steps, forKey: .steps)
        try c.encodeIfPresent(activeEnergyKcal, forKey: .activeEnergyKcal)
        try c.encodeIfPresent(exerciseMinutes, forKey: .exerciseMinutes)
        try c.encode(source, forKey: .source)
    }
}
