import Foundation

private func reminder(_ h: Int, _ m: Int, weekdays: Set<Int> = DailyReminder.everyDay, enabled: Bool = true) -> DailyReminder {
    DailyReminder(hour: h, minute: m, note: "", weekdays: weekdays, isEnabled: enabled)
}

// 2026-09-30 is a Wednesday (weekday 4).

private func testNextFireLaterToday() {
    let r = reminder(23, 0)
    let next = r.nextFireDate(after: date(2026, 9, 30, 22, 0), calendar: shanghai)
    expect(next == date(2026, 9, 30, 23, 0), "fires later the same day, got \(String(describing: next))")
}

private func testNextFireRollsToTomorrow() {
    let r = reminder(23, 0)
    let next = r.nextFireDate(after: date(2026, 9, 30, 23, 30), calendar: shanghai)
    expect(next == date(2026, 10, 1, 23, 0), "rolls over to tomorrow, got \(String(describing: next))")
}

private func testNextFireIsStrictlyAfter() {
    let r = reminder(23, 0)
    let next = r.nextFireDate(after: date(2026, 9, 30, 23, 0), calendar: shanghai)
    expect(next == date(2026, 10, 1, 23, 0), "exact fire time is not 'after', got \(String(describing: next))")
}

private func testNextFireRespectsWeekdays() {
    // Weekdays only (Mon–Fri = 2...6). Friday 2026-10-02 23:30 → next is Monday 10-05.
    let r = reminder(23, 0, weekdays: [2, 3, 4, 5, 6])
    let next = r.nextFireDate(after: date(2026, 10, 2, 23, 30), calendar: shanghai)
    expect(next == date(2026, 10, 5, 23, 0), "skips the weekend, got \(String(describing: next))")
}

private func testDisabledOrNoWeekdaysNeverFires() {
    let now = date(2026, 9, 30, 22, 0)
    expect(reminder(23, 0, enabled: false).nextFireDate(after: now, calendar: shanghai) == nil, "disabled → nil")
    expect(reminder(23, 0, weekdays: []).nextFireDate(after: now, calendar: shanghai) == nil, "no weekdays → nil")
}

private func testNextFireAcrossDSTGap() {
    // US spring-forward 2026-03-08: 02:30 doesn't exist in New York; should still fire that morning.
    let ny = calendar("America/New_York")
    let r = reminder(2, 30)
    let next = r.nextFireDate(after: date(2026, 3, 8, 0, 0, cal: ny), calendar: ny)!
    expect(ny.isDate(next, inSameDayAs: date(2026, 3, 8, 12, 0, cal: ny)), "fires on the DST day, got \(next)")
}

private func testScheduleNextPicksEarliest() {
    let a = reminder(23, 0)
    let b = reminder(22, 30)
    let result = ReminderSchedule.next(in: [a, b], after: date(2026, 9, 30, 22, 0), calendar: shanghai)
    expect(result?.reminder.id == b.id, "earliest reminder wins")
    expect(result?.date == date(2026, 9, 30, 22, 30), "earliest date, got \(String(describing: result?.date))")
}

private func testDueOnTime() {
    let r = reminder(23, 0)
    let due = ReminderSchedule.due(
        in: [r], from: date(2026, 9, 30, 22, 59, 50), to: date(2026, 9, 30, 23, 0, 1),
        grace: 30 * 60, calendar: shanghai
    )
    expect(due.map(\.reminder.id) == [r.id], "fires when the window crosses the time")
    expect(due.first?.date == date(2026, 9, 30, 23, 0), "reports the occurrence time")
}

private func testDueNotYet() {
    let due = ReminderSchedule.due(
        in: [reminder(23, 0)], from: date(2026, 9, 30, 22, 0), to: date(2026, 9, 30, 22, 59),
        grace: 30 * 60, calendar: shanghai
    )
    expect(due.isEmpty, "nothing due before the time")
}

private func testDueAfterShortSleepWithinGrace() {
    // Lid closed 22:50, opened 23:20 → still show the 23:00 reminder.
    let due = ReminderSchedule.due(
        in: [reminder(23, 0)], from: date(2026, 9, 30, 22, 50), to: date(2026, 9, 30, 23, 20),
        grace: 30 * 60, calendar: shanghai
    )
    expect(due.count == 1, "missed reminder within grace is shown")
}

private func testDueAfterLongSleepSkipped() {
    // Lid closed 22:50, opened next morning 08:00 → too late, don't nag.
    let due = ReminderSchedule.due(
        in: [reminder(23, 0)], from: date(2026, 9, 30, 22, 50), to: date(2026, 10, 1, 8, 0),
        grace: 30 * 60, calendar: shanghai
    )
    expect(due.isEmpty, "stale reminder beyond grace is skipped")
}

private func testDueAfterMultiDaySleepUsesLatestOccurrence() {
    // Asleep for two days, woke at 23:10 on the third day → the latest 23:00 is within grace.
    let due = ReminderSchedule.due(
        in: [reminder(23, 0)], from: date(2026, 9, 28, 20, 0), to: date(2026, 9, 30, 23, 10),
        grace: 30 * 60, calendar: shanghai
    )
    expect(due.count == 1, "latest occurrence within grace fires once")
}

private func testDueSortedByOccurrenceNotArrayOrder() {
    // Asleep 22:25–22:55: both 22:50 (row 1) and 22:30 (row 2) are within grace.
    let late = reminder(22, 50)
    let early = reminder(22, 30)
    let due = ReminderSchedule.due(
        in: [late, early], from: date(2026, 9, 30, 22, 25), to: date(2026, 9, 30, 22, 55),
        grace: 30 * 60, calendar: shanghai
    )
    expect(due.map(\.reminder.id) == [early.id, late.id], "sorted oldest → newest, so .last is the latest")
}

private func testDueLooksForwardFromLastCheck() {
    // Reminder for 22:30 created at 22:40 (lastCheck reset to 22:40) → not treated as missed at 22:50.
    let due = ReminderSchedule.due(
        in: [reminder(22, 30)], from: date(2026, 9, 30, 22, 40), to: date(2026, 9, 30, 22, 50),
        grace: 30 * 60, calendar: shanghai
    )
    expect(due.isEmpty, "occurrence before lastCheck is not due")
}

// MARK: - Days summary

private var chinese: Calendar {
    var cal = shanghai
    cal.locale = Locale(identifier: "zh_CN")
    return cal
}

private func testDaysSummary() { with(.zh) {
    func summary(_ days: Set<Int>) -> String { reminder(23, 0, weekdays: days).daysSummary(calendar: chinese) }
    expect(summary(DailyReminder.everyDay) == "每天", "all seven days")
    expect(summary([2, 3, 4, 5, 6]) == "工作日", "Mon–Fri")
    expect(summary([1, 7]) == "周末", "Sat + Sun")
    expect(summary([]) == "从不", "no days")
    expect(summary([6, 2, 4]) == "周一 周三 周五", "others listed in week order, got \(summary([6, 2, 4]))")
} }

// MARK: - Snooze

private func testSnoozeLimit() {
    let id = UUID()
    let at = date(2026, 9, 30, 23, 10)
    expect(SnoozeState(reminderID: id, fireDate: at, count: 0).canSnoozeAgain, "original alert can snooze")
    expect(SnoozeState(reminderID: id, fireDate: at, count: 2).canSnoozeAgain, "after 2 snoozes, a 3rd is allowed")
    expect(!SnoozeState(reminderID: id, fireDate: at, count: 3).canSnoozeAgain, "after 3 snoozes, no more")
}

private func testSnoozeRestoreFuture() {
    let s = SnoozeState(reminderID: UUID(), fireDate: date(2026, 9, 30, 23, 10), count: 1)
    let action = s.restoreAction(now: date(2026, 9, 30, 23, 5), grace: 30 * 60)
    expect(action == .schedule(date(2026, 9, 30, 23, 10)), "pending snooze is re-armed after relaunch, got \(action)")
}

private func testSnoozeRestoreJustMissed() {
    let s = SnoozeState(reminderID: UUID(), fireDate: date(2026, 9, 30, 23, 10), count: 1)
    let action = s.restoreAction(now: date(2026, 9, 30, 23, 20), grace: 30 * 60)
    expect(action == .fireNow, "snooze that came due while Tick was closed fires on launch, got \(action)")
}

private func testSnoozeRestoreStale() {
    let s = SnoozeState(reminderID: UUID(), fireDate: date(2026, 9, 30, 23, 10), count: 1)
    let action = s.restoreAction(now: date(2026, 10, 1, 8, 0), grace: 30 * 60)
    expect(action == .discard, "snooze from last night is dropped, got \(action)")
}

private func testSnoozeCodable() {
    let s = SnoozeState(reminderID: UUID(), fireDate: date(2026, 9, 30, 23, 10), count: 2)
    let decoded = try! JSONDecoder().decode(SnoozeState.self, from: try! JSONEncoder().encode(s))
    expect(decoded == s, "snooze state round-trips through JSON")
}

private func testLaunchCheckpoint() {
    let now = date(2026, 9, 30, 23, 17)
    let grace: TimeInterval = 30 * 60
    // Fresh install / nothing saved: look back the full grace window (launch at login after bedtime)
    expect(ReminderSchedule.launchCheckpoint(saved: nil, now: now, grace: grace) == date(2026, 9, 30, 22, 47),
           "no saved checkpoint → now - grace")
    // Quit at 23:14 right after the 23:13 alert, relaunched 23:17: don't show 23:13 again
    expect(ReminderSchedule.launchCheckpoint(saved: date(2026, 9, 30, 23, 14), now: now, grace: grace) == date(2026, 9, 30, 23, 14),
           "recent checkpoint wins")
    // Quit yesterday: only the grace window matters
    expect(ReminderSchedule.launchCheckpoint(saved: date(2026, 9, 29, 9, 0), now: now, grace: grace) == date(2026, 9, 30, 22, 47),
           "stale checkpoint → now - grace")
    // Clock moved backwards: never start in the future
    expect(ReminderSchedule.launchCheckpoint(saved: date(2026, 10, 1, 9, 0), now: now, grace: grace) == now,
           "future checkpoint clamps to now")
}

private func testCodableRoundTrip() {
    let r = DailyReminder(hour: 22, minute: 45, note: "Wind down", weekdays: [1, 7], isEnabled: false)
    let data = try! JSONEncoder().encode([r])
    let decoded = try! JSONDecoder().decode([DailyReminder].self, from: data)
    expect(decoded == [r], "round-trips through JSON")
}

private func testTimeLabel() {
    expect(reminder(7, 5).timeLabel == "07:05", "zero-padded HH:mm")
}

let scheduleTests: [(String, () -> Void)] = [
    ("nextFireLaterToday", testNextFireLaterToday),
    ("nextFireRollsToTomorrow", testNextFireRollsToTomorrow),
    ("nextFireIsStrictlyAfter", testNextFireIsStrictlyAfter),
    ("nextFireRespectsWeekdays", testNextFireRespectsWeekdays),
    ("disabledOrNoWeekdaysNeverFires", testDisabledOrNoWeekdaysNeverFires),
    ("nextFireAcrossDSTGap", testNextFireAcrossDSTGap),
    ("scheduleNextPicksEarliest", testScheduleNextPicksEarliest),
    ("dueOnTime", testDueOnTime),
    ("dueNotYet", testDueNotYet),
    ("dueAfterShortSleepWithinGrace", testDueAfterShortSleepWithinGrace),
    ("dueAfterLongSleepSkipped", testDueAfterLongSleepSkipped),
    ("dueAfterMultiDaySleepUsesLatestOccurrence", testDueAfterMultiDaySleepUsesLatestOccurrence),
    ("dueSortedByOccurrenceNotArrayOrder", testDueSortedByOccurrenceNotArrayOrder),
    ("dueLooksForwardFromLastCheck", testDueLooksForwardFromLastCheck),
    ("daysSummary", testDaysSummary),
    ("snoozeLimit", testSnoozeLimit),
    ("snoozeRestoreFuture", testSnoozeRestoreFuture),
    ("snoozeRestoreJustMissed", testSnoozeRestoreJustMissed),
    ("snoozeRestoreStale", testSnoozeRestoreStale),
    ("snoozeCodable", testSnoozeCodable),
    ("launchCheckpoint", testLaunchCheckpoint),
    ("codableRoundTrip", testCodableRoundTrip),
    ("timeLabel", testTimeLabel),
]
