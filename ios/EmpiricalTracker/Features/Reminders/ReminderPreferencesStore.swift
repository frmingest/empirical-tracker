import Foundation
import Observation

/// User-facing reminder preferences, persisted via `UserDefaults`.
///
/// All reminders are **local notifications scheduled on this device** — nothing is
/// sent to or stored on the backend (`ReminderScheduler` owns the actual
/// `UNUserNotificationCenter` requests). Everything defaults to off: reminders are
/// strictly opt-in.
@MainActor
@Observable
public final class ReminderPreferencesStore {

    // MARK: - State

    /// Daily "log today's meals" nudge.
    public var mealReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(mealReminderEnabled, forKey: Keys.mealEnabled) }
    }

    /// Minutes from local midnight for the meal reminder (default 19:30).
    public var mealReminderMinutes: Int {
        didSet { UserDefaults.standard.set(mealReminderMinutes, forKey: Keys.mealMinutes) }
    }

    /// Daily morning weigh-in nudge.
    public var weightReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(weightReminderEnabled, forKey: Keys.weightEnabled) }
    }

    /// Minutes from local midnight for the weigh-in reminder (default 08:00).
    public var weightReminderMinutes: Int {
        didSet { UserDefaults.standard.set(weightReminderMinutes, forKey: Keys.weightMinutes) }
    }

    /// One-shot "time for a new blood panel" nudge ~3 months after the latest panel.
    public var labReminderEnabled: Bool {
        didSet { UserDefaults.standard.set(labReminderEnabled, forKey: Keys.labEnabled) }
    }

    /// The fire date last scheduled for the lab reminder. Kept so an app launch that
    /// hasn't fetched panels yet doesn't silently postpone an already-armed nudge.
    public var labReminderFireAt: Date? {
        didSet { UserDefaults.standard.set(labReminderFireAt, forKey: Keys.labFireAt) }
    }

    // MARK: - Init

    public init() {
        let d = UserDefaults.standard
        mealReminderEnabled   = d.bool(forKey: Keys.mealEnabled)
        mealReminderMinutes   = d.object(forKey: Keys.mealMinutes) as? Int ?? 19 * 60 + 30
        weightReminderEnabled = d.bool(forKey: Keys.weightEnabled)
        weightReminderMinutes = d.object(forKey: Keys.weightMinutes) as? Int ?? 8 * 60
        labReminderEnabled    = d.bool(forKey: Keys.labEnabled)
        labReminderFireAt     = d.object(forKey: Keys.labFireAt) as? Date
    }

    // MARK: - Time-of-day bridging (for DatePicker bindings)

    public var mealReminderTime: Date {
        get { Self.time(fromMinutes: mealReminderMinutes) }
        set { mealReminderMinutes = Self.minutes(from: newValue) }
    }

    public var weightReminderTime: Date {
        get { Self.time(fromMinutes: weightReminderMinutes) }
        set { weightReminderMinutes = Self.minutes(from: newValue) }
    }

    private static func time(fromMinutes minutes: Int) -> Date {
        let start = Calendar.current.startOfDay(for: .now)
        return Calendar.current.date(byAdding: .minute, value: minutes, to: start) ?? start
    }

    private static func minutes(from date: Date) -> Int {
        let comps = Calendar.current.dateComponents([.hour, .minute], from: date)
        return (comps.hour ?? 0) * 60 + (comps.minute ?? 0)
    }

    // MARK: - Keys

    private enum Keys {
        static let mealEnabled   = "reminders.meal.enabled"
        static let mealMinutes   = "reminders.meal.minutes"
        static let weightEnabled = "reminders.weight.enabled"
        static let weightMinutes = "reminders.weight.minutes"
        static let labEnabled    = "reminders.lab.enabled"
        static let labFireAt     = "reminders.lab.fireAt"
    }
}
