import Foundation
import UserNotifications

/// Schedules the app's local reminders from `ReminderPreferencesStore`.
///
/// Three notifications exist, each with a stable identifier so re-syncing replaces
/// rather than stacks:
///   - `reminder.meal`   — repeating daily, "log today's meals"
///   - `reminder.weight` — repeating daily, "morning weigh-in"
///   - `reminder.lab`    — one-shot, ~3 months after the latest blood panel, because
///     the app's hero data arrives on a quarterly lab cadence and a single panel
///     never draws a trend line
///
/// Everything is local to the device; no push infrastructure and no server state.
@MainActor
enum ReminderScheduler {

    static let mealID   = "reminder.meal"
    static let weightID = "reminder.weight"
    static let labID    = "reminder.lab"

    /// Days after the most recent blood draw before the re-test nudge fires.
    static let labCadenceDays = 90

    // MARK: - Authorization

    /// Asks for notification permission (no-op if already determined).
    /// Returns true when notifications may be delivered.
    static func requestAuthorization() async -> Bool {
        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied:
            return false
        default:
            return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        }
    }

    // MARK: - Sync

    /// Replaces all pending app reminders with the current preferences.
    /// `latestPanelDate` anchors the lab-cadence nudge; when the caller hasn't
    /// fetched panels, the previously stored fire date is kept rather than postponed.
    static func sync(prefs: ReminderPreferencesStore, latestPanelDate: Date?) async {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [mealID, weightID, labID])

        guard prefs.mealReminderEnabled || prefs.weightReminderEnabled || prefs.labReminderEnabled else {
            return
        }

        if prefs.mealReminderEnabled {
            try? await center.add(dailyRequest(
                id: mealID,
                minutesFromMidnight: prefs.mealReminderMinutes,
                title: String(localized: "notification.meal.title"),
                body: String(localized: "notification.meal.body")
            ))
        }

        if prefs.weightReminderEnabled {
            try? await center.add(dailyRequest(
                id: weightID,
                minutesFromMidnight: prefs.weightReminderMinutes,
                title: String(localized: "notification.weight.title"),
                body: String(localized: "notification.weight.body")
            ))
        }

        if prefs.labReminderEnabled {
            let fireAt = labFireDate(latestPanelDate: latestPanelDate, stored: prefs.labReminderFireAt)
            prefs.labReminderFireAt = fireAt

            let content = UNMutableNotificationContent()
            content.title = String(localized: "notification.lab.title")
            content.body  = String(localized: "notification.lab.body")
            content.sound = .default

            let comps = Calendar.current.dateComponents(
                [.year, .month, .day, .hour, .minute], from: fireAt
            )
            let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: false)
            try? await center.add(UNNotificationRequest(identifier: labID, content: content, trigger: trigger))
        }
    }

    // MARK: - Helpers

    private static func dailyRequest(
        id: String,
        minutesFromMidnight: Int,
        title: String,
        body: String
    ) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body  = body
        content.sound = .default

        var comps = DateComponents()
        comps.hour   = minutesFromMidnight / 60
        comps.minute = minutesFromMidnight % 60
        let trigger = UNCalendarNotificationTrigger(dateMatching: comps, repeats: true)
        return UNNotificationRequest(identifier: id, content: content, trigger: trigger)
    }

    /// Picks the lab-nudge fire date (10:00 local):
    ///   - latest panel + 90 days when a panel date is known;
    ///   - if that is already past (importing old data), a gentle one week out;
    ///   - the previously stored future date when panels haven't been fetched;
    ///   - otherwise 90 days from today.
    private static func labFireDate(latestPanelDate: Date?, stored: Date?) -> Date {
        let cal = Calendar.current
        let now = Date()
        var fire: Date
        if let anchor = latestPanelDate {
            fire = cal.date(byAdding: .day, value: labCadenceDays, to: anchor) ?? now
            if fire <= now {
                fire = cal.date(byAdding: .day, value: 7, to: now) ?? now
            }
        } else if let stored, stored > now {
            return stored
        } else {
            fire = cal.date(byAdding: .day, value: labCadenceDays, to: now) ?? now
        }
        var comps = cal.dateComponents([.year, .month, .day], from: fire)
        comps.hour = 10
        return cal.date(from: comps) ?? fire
    }
}
