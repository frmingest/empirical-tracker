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

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withFullDate]
        fmt.timeZone = TimeZone(secondsFromGMT: 0)
        try c.encode(fmt.string(from: measuredOn), forKey: .measuredOn)
        try c.encodeIfPresent(steps, forKey: .steps)
        try c.encodeIfPresent(activeEnergyKcal, forKey: .activeEnergyKcal)
        try c.encodeIfPresent(exerciseMinutes, forKey: .exerciseMinutes)
        try c.encode(source, forKey: .source)
    }
}
