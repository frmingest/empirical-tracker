import Core
import Foundation
import Observation

/// Device-local record of which calendar days had at least one logging action
/// (food entry or body metric). Powers the quiet streak / last-7-days line in the
/// food diary — feedback that the habit is forming, without badges or levels.
///
/// Intentionally local: it tracks *this device's* logging behaviour and is not
/// part of the user's health record (so it is also not in the GDPR export, which
/// covers backend data).
@MainActor
@Observable
public final class LoggingActivityStore {

    /// Days with at least one log, as `yyyy-MM-dd` strings (local calendar).
    private(set) var days: Set<String>

    private static let key = "logging.activity.days"
    /// Window kept on disk — enough for streaks without growing unbounded.
    private static let retentionDays = 90

    public init() {
        days = Set(UserDefaults.standard.stringArray(forKey: Self.key) ?? [])
    }

    // MARK: - Recording

    public func recordToday() {
        let today = CalendarDate.string(from: .now)
        guard !days.contains(today) else { return }
        days.insert(today)
        prune()
        UserDefaults.standard.set(Array(days), forKey: Self.key)
    }

    // MARK: - Derived

    /// Consecutive logged days ending today — or ending yesterday, so an unbroken
    /// streak isn't shown as zero before the user has logged anything today.
    public var currentStreak: Int {
        let cal = Calendar.current
        var anchor = cal.startOfDay(for: .now)
        if !days.contains(CalendarDate.string(from: anchor)) {
            guard let yesterday = cal.date(byAdding: .day, value: -1, to: anchor) else { return 0 }
            anchor = yesterday
        }
        var streak = 0
        var day = anchor
        while days.contains(CalendarDate.string(from: day)) {
            streak += 1
            guard let previous = cal.date(byAdding: .day, value: -1, to: day) else { break }
            day = previous
        }
        return streak
    }

    /// How many of the last 7 calendar days (including today) had a log.
    public var daysLoggedLast7: Int {
        let cal = Calendar.current
        let today = cal.startOfDay(for: .now)
        return (0..<7).reduce(0) { count, offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: today) else { return count }
            return count + (days.contains(CalendarDate.string(from: day)) ? 1 : 0)
        }
    }

    // MARK: - Private

    private func prune() {
        let cal = Calendar.current
        guard let cutoff = cal.date(byAdding: .day, value: -Self.retentionDays, to: .now) else { return }
        let cutoffString = CalendarDate.string(from: cutoff)
        // yyyy-MM-dd sorts lexicographically in date order.
        days = days.filter { $0 >= cutoffString }
    }
}
