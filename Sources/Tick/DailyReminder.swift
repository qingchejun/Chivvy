import Foundation

struct DailyReminder: Identifiable, Codable, Equatable {
    var id: UUID
    var hour: Int
    var minute: Int
    var note: String
    /// Calendar weekdays: 1 = Sunday … 7 = Saturday
    var weekdays: Set<Int>
    var isEnabled: Bool

    static let everyDay: Set<Int> = Set(1...7)
    static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]
    static let weekendsOnly: Set<Int> = [1, 7]
    /// Every-day reminders use 1 system notification, others up to 7; macOS keeps at most 64 pending
    static let maxCount = 8

    init(id: UUID = UUID(), hour: Int, minute: Int, note: String = "",
         weekdays: Set<Int> = everyDay, isEnabled: Bool = true) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.note = note
        self.weekdays = weekdays
        self.isEnabled = isEnabled
    }

    var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }

    func daysSummary(calendar: Calendar = .current) -> String {
        switch weekdays {
        case Self.everyDay: return L("每天", "Every day")
        case Self.weekdaysOnly: return L("工作日", "Weekdays")
        case Self.weekendsOnly: return L("周末", "Weekends")
        case []: return L("从不", "Never")
        default:
            return Self.orderedWeekdays(calendar: calendar)
                .filter(weekdays.contains)
                .map { Self.shortName(weekday: $0) }
                .joined(separator: " ")
        }
    }

    /// Weekday names in the UI language (not the system locale), 1 = Sunday
    static func shortName(weekday: Int) -> String {
        L(["周日", "周一", "周二", "周三", "周四", "周五", "周六"][weekday - 1],
          ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][weekday - 1])
    }

    static func letter(weekday: Int) -> String {
        L(["日", "一", "二", "三", "四", "五", "六"][weekday - 1],
          ["S", "M", "T", "W", "T", "F", "S"][weekday - 1])
    }

    /// Weekdays ordered from the user's first weekday (e.g. Mon…Sun or Sun…Sat)
    static func orderedWeekdays(calendar: Calendar = .current) -> [Int] {
        (0..<7).map { (calendar.firstWeekday - 1 + $0) % 7 + 1 }
    }

    /// Earliest fire time strictly after `date`, or nil if the reminder never fires.
    func nextFireDate(after date: Date, calendar: Calendar = .current) -> Date? {
        guard isEnabled else { return nil }
        return weekdays.compactMap { weekday in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                matchingPolicy: .nextTime
            )
        }.min()
    }
}

/// A reminder paired with one concrete occurrence time
struct ScheduledReminder: Equatable {
    let reminder: DailyReminder
    let date: Date
}

enum ReminderSchedule {
    static func next(in reminders: [DailyReminder], after date: Date,
                     calendar: Calendar = .current) -> ScheduledReminder? {
        reminders
            .compactMap { r in r.nextFireDate(after: date, calendar: calendar).map { ScheduledReminder(reminder: r, date: $0) } }
            .min { $0.date < $1.date }
    }

    /// Where the first check after launch starts looking back from.
    /// Picks up from the last check before quitting, so an alert already shown isn't shown again,
    /// but never further back than `grace` and never in the future.
    static func launchCheckpoint(saved: Date?, now: Date, grace: TimeInterval) -> Date {
        let earliest = now.addingTimeInterval(-grace)
        guard let saved else { return earliest }
        return min(max(saved, earliest), now)
    }

    /// Occurrences in (from, to] no older than `grace`, oldest first.
    /// Covers on-time firing as well as occurrences missed while the Mac was asleep.
    static func due(in reminders: [DailyReminder], from: Date, to: Date,
                    grace: TimeInterval, calendar: Calendar = .current) -> [ScheduledReminder] {
        let earliestAllowed = max(from, to.addingTimeInterval(-grace))
        return reminders
            .compactMap { r in
                // The only occurrence that matters is the first one after max(from, to - grace).
                guard let fire = r.nextFireDate(after: earliestAllowed, calendar: calendar), fire <= to else { return nil }
                return ScheduledReminder(reminder: r, date: fire)
            }
            .sorted { $0.date < $1.date }
    }
}

/// A pending "N more min" for one reminder occurrence. Persisted so it survives a relaunch.
struct SnoozeState: Codable, Equatable {
    let reminderID: UUID
    let fireDate: Date
    /// Snoozes already used for this occurrence
    let count: Int

    static let maxCount = 3

    var canSnoozeAgain: Bool { count < Self.maxCount }

    enum RestoreAction: Equatable {
        case schedule(Date)
        case fireNow
        case discard
    }

    func restoreAction(now: Date, grace: TimeInterval) -> RestoreAction {
        if fireDate > now { return .schedule(fireDate) }
        return now.timeIntervalSince(fireDate) <= grace ? .fireNow : .discard
    }
}
