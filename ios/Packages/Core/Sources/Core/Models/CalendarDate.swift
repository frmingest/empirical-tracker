import Foundation

/// Formats and parses backend **calendar dates** (`yyyy-MM-dd` columns such as
/// `logged_on`, `measured_on`, `scheduled_on`, `tested_at`) in the user's
/// *current* time zone.
///
/// A calendar date names a local day, not an instant. Serialising a
/// midnight-local `Date` through a UTC formatter (or `JSONEncoder`'s `.iso8601`
/// strategy) shifts the day backwards for positive-offset time zones — e.g.
/// `2026-06-10` 00:00 CEST becomes `2026-06-09T22:00:00Z`, filing the row under
/// the wrong day. This bug was fixed independently in `ManualResultPayload`,
/// `PlannedMealPayload`, and `MealPlansRepository` before being centralised
/// here; every new date-only field **must** go through this helper.
public enum CalendarDate {

    /// Shared formatter pinned to the current time zone.
    public static let formatter: DateFormatter = makeFormatter(timeZone: .current)

    /// `Date` → `"yyyy-MM-dd"` on the local calendar day the date falls on.
    public static func string(from date: Date) -> String {
        formatter.string(from: date)
    }

    /// `"yyyy-MM-dd"` → local midnight of that calendar day.
    public static func date(from string: String) -> Date? {
        formatter.date(from: string)
    }

    /// Formatter factory for tests that need to pin a specific time zone.
    public static func makeFormatter(timeZone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = timeZone
        f.dateFormat = "yyyy-MM-dd"
        return f
    }
}
