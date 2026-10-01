import Foundation

/// A date with no time zone attached: "Oct 3" stays Oct 3 after flying to another time zone
struct CalendarDay: Codable, Hashable {
    var year: Int
    var month: Int
    var day: Int

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        self.init(year: parts.year ?? 2001, month: parts.month ?? 1, day: parts.day ?? 1)
    }

    /// Midnight of this day in `calendar`'s time zone
    func start(calendar: Calendar = .current) -> Date? {
        calendar.date(from: DateComponents(year: year, month: month, day: day))
    }
}

struct DailyReminder: Identifiable, Codable, Equatable {
    var id: UUID
    var hour: Int
    var minute: Int
    var note: String
    /// Calendar weekdays: 1 = Sunday … 7 = Saturday
    var weekdays: Set<Int>
    var isEnabled: Bool
    /// Set for a one-time reminder: the day it fires, `weekdays` is ignored. nil = repeating.
    var day: CalendarDay?

    static let everyDay: Set<Int> = Set(1...7)
    static let weekdaysOnly: Set<Int> = [2, 3, 4, 5, 6]
    static let weekendsOnly: Set<Int> = [1, 7]
    /// Every-day reminders use 1 system notification, others up to 7; macOS keeps at most 64 pending
    static let maxCount = 8

    init(id: UUID = UUID(), hour: Int, minute: Int, note: String = "",
         weekdays: Set<Int> = everyDay, isEnabled: Bool = true, day: CalendarDay? = nil) {
        self.id = id
        self.hour = hour
        self.minute = minute
        self.note = note
        self.weekdays = weekdays
        self.isEnabled = isEnabled
        self.day = day
    }

    var isOneOff: Bool { day != nil }

    /// The one moment a one-off fires; nil for repeating reminders
    func oneOffDate(calendar: Calendar = .current) -> Date? {
        day?.start(calendar: calendar).flatMap { calendar.date(bySettingHour: hour, minute: minute, second: 0, of: $0) }
    }

    /// Whether turning it on would ever fire: a repeating one needs days, a one-off a time still ahead
    func canFire(now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if isOneOff { return oneOffDate(calendar: calendar).map { $0 > now } ?? false }
        return !weekdays.isEmpty
    }

    var timeLabel: String {
        String(format: "%02d:%02d", hour, minute)
    }

    func daysSummary(calendar: Calendar = .current) -> String {
        if isOneOff { return L("仅一次", "Once") }
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
        if isOneOff {
            return oneOffDate(calendar: calendar).flatMap { $0 > date ? $0 : nil }
        }
        return weekdays.compactMap { weekday in
            calendar.nextDate(
                after: date,
                matching: DateComponents(hour: hour, minute: minute, weekday: weekday),
                matchingPolicy: .nextTime
            )
        }.min()
    }
}

extension DailyReminder {
    /// "今天" / "明天" / "周三" for a coming occurrence, "10月8日" a week or more away
    static func relativeDayLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: now),
                                           to: calendar.startOfDay(for: date)).day ?? 0
        if days == 0 { return L("今天", "Today") }
        if days == 1 { return L("明天", "Tomorrow") }
        if (2..<7).contains(days) { return shortName(weekday: calendar.component(.weekday, from: date)) }
        let parts = calendar.dateComponents([.month, .day], from: date)
        let month = parts.month ?? 1, day = parts.day ?? 1
        let months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
        return L("\(month)月\(day)日", "\(months[month - 1]) \(day)")
    }

    /// When it fires, in words: "今天" for a one-off, "工作日" for a repeating one
    func scheduleSummary(now: Date = Date(), calendar: Calendar = .current) -> String {
        guard let fire = oneOffDate(calendar: calendar) else { return daysSummary(calendar: calendar) }
        return Self.relativeDayLabel(fire, now: now, calendar: calendar)
    }

    /// Like `relativeDayLabel`, but "13 分钟后" within the hour
    static func whenLabel(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let seconds = date.timeIntervalSince(now)
        if seconds > 0 && seconds <= 3600 {
            let minutes = Int((seconds / 60).rounded(.up))
            return L("\(minutes) 分钟后", "in \(minutes) min")
        }
        return relativeDayLabel(date, now: now, calendar: calendar)
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

    /// One-offs that are done: their time has passed and they were shown (`fired`), or they're too old
    /// to still be shown as missed. Never one that's `busy` (alert on screen or snooze pending).
    static func prunableOneOffs(in reminders: [DailyReminder], now: Date, grace: TimeInterval,
                                fired: Set<UUID>, busy: Set<UUID>, calendar: Calendar = .current) -> [UUID] {
        reminders.compactMap { r in
            guard let fire = r.oneOffDate(calendar: calendar), fire <= now, !busy.contains(r.id) else { return nil }
            return fired.contains(r.id) || fire < now.addingTimeInterval(-grace) ? r.id : nil
        }
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
