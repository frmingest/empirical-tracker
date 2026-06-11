import Testing
import Foundation
@testable import Core

/// Locks the calendar-date wire contract (`yyyy-MM-dd` columns: `logged_on`,
/// `measured_on`, `scheduled_on`, `started_on`, `tested_at`): a calendar date
/// names a *local* day, so formatting and parsing must happen in the user's
/// time zone. Serialising local midnight through UTC shifts the day backwards
/// for positive-offset zones — the bug fixed (repeatedly) by `CalendarDate`.
struct CalendarDateTests {

    private let oslo = TimeZone(identifier: "Europe/Oslo")!
    private let losAngeles = TimeZone(identifier: "America/Los_Angeles")!

    private func midnight(year: Int, month: Int, day: Int, in zone: TimeZone) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = zone
        return cal.date(from: DateComponents(year: year, month: month, day: day))!
    }

    // MARK: - Formatting

    /// Midnight local in a positive-offset zone must format as that same day —
    /// a UTC formatter would emit the previous day (00:00 CEST = 22:00Z − 1 day).
    @Test func formatsLocalMidnightAsSameDayInPositiveOffsetZone() {
        let date = midnight(year: 2026, month: 6, day: 10, in: oslo)

        let osloFormatter = CalendarDate.makeFormatter(timeZone: oslo)
        #expect(osloFormatter.string(from: date) == "2026-06-10")

        // The exact failure mode this helper exists to prevent:
        let utcFormatter = CalendarDate.makeFormatter(timeZone: TimeZone(secondsFromGMT: 0)!)
        #expect(utcFormatter.string(from: date) == "2026-06-09")
    }

    @Test func formatsLocalMidnightAsSameDayInNegativeOffsetZone() {
        let date = midnight(year: 2026, month: 6, day: 10, in: losAngeles)
        let laFormatter = CalendarDate.makeFormatter(timeZone: losAngeles)
        #expect(laFormatter.string(from: date) == "2026-06-10")
    }

    // MARK: - Parsing

    /// A parsed calendar date must land on that day of the *parsing* zone's
    /// calendar, so views grouping with `Calendar.current` show the right day.
    @Test func parsesToLocalMidnightOfNamedDay() throws {
        let laFormatter = CalendarDate.makeFormatter(timeZone: losAngeles)
        let parsed = try #require(laFormatter.date(from: "2026-06-10"))

        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = losAngeles
        let comps = cal.dateComponents([.year, .month, .day, .hour], from: parsed)
        #expect(comps.year == 2026 && comps.month == 6 && comps.day == 10)
        #expect(comps.hour == 0)
    }

    // MARK: - Round trip in the current zone

    @Test func roundTripsTodayInCurrentZone() throws {
        let todayMidnight = Calendar.current.startOfDay(for: .now)
        let encoded = CalendarDate.string(from: todayMidnight)
        let decoded = try #require(CalendarDate.date(from: encoded))
        #expect(decoded == todayMidnight)
    }

    // MARK: - Payload contracts

    /// `FoodEntryPayload.logged_on` must carry the local diary day, not a UTC
    /// instant (which Postgres would truncate to the wrong `date`).
    @Test func foodEntryPayloadEncodesLoggedOnAsLocalCalendarDate() throws {
        let day = Calendar.current.date(from: DateComponents(year: 2026, month: 6, day: 10))!
        let payload = FoodEntryPayload(loggedOn: day, meal: .dinner, foodName: "Ribeye")

        let data = try JSONEncoder.api.encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["logged_on"] as? String == "2026-06-10")
        #expect(object["food_name"] as? String == "Ribeye")
    }

    /// `DietEventPayload.started_on` / `ended_on` likewise.
    @Test func dietEventPayloadEncodesDatesAsLocalCalendarDates() throws {
        let start = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 1))!
        let end = Calendar.current.date(from: DateComponents(year: 2026, month: 3, day: 14))!
        let payload = DietEventPayload(label: "Fast", kind: .fast, startedOn: start, endedOn: end)

        let data = try JSONEncoder.api.encode(payload)
        let object = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["started_on"] as? String == "2026-03-01")
        #expect(object["ended_on"] as? String == "2026-03-14")
        #expect(object["label"] as? String == "Fast")
        #expect(object["kind"] as? String == "fast")
    }

    /// Date-only strings from the backend decode to *local* midnight, so
    /// `Calendar.current` groupings (diary days, "today" widget filter) see the
    /// day the backend named.
    @Test func apiDecoderParsesDateOnlyStringsAsLocalDays() throws {
        let json = """
        { "id": "e1", "logged_on": "2026-06-08", "meal": "lunch", "food_name": "Egg" }
        """.data(using: .utf8)!

        let entry = try JSONDecoder.api.decode(FoodEntry.self, from: json)
        let comps = Calendar.current.dateComponents([.year, .month, .day], from: entry.loggedOn)
        #expect(comps.year == 2026 && comps.month == 6 && comps.day == 8)
    }
}
