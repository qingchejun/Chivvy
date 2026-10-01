import Foundation

// One-time reminders: "7点钟提醒我睡觉" fires once, at the nearest 7 o'clock.
// 2026-09-30 is a Wednesday (weekday 4).

private func oneOff(_ h: Int, _ m: Int, on day: CalendarDay, enabled: Bool = true) -> DailyReminder {
    DailyReminder(hour: h, minute: m, note: "", isEnabled: enabled, day: day)
}

private func cday(_ y: Int, _ m: Int, _ d: Int) -> CalendarDay { CalendarDay(year: y, month: m, day: d) }

// MARK: - Model

private func testOneOffFiresOnce() {
    let r = oneOff(19, 0, on: cday(2026, 9, 30))
    expect(r.isOneOff, "has a day → one-off")
    expect(r.nextFireDate(after: date(2026, 9, 30, 12, 0), calendar: shanghai) == date(2026, 9, 30, 19, 0),
           "fires at 19:00 that day")
    expect(r.nextFireDate(after: date(2026, 9, 30, 19, 0), calendar: shanghai) == nil, "never fires again")
    expect(oneOff(19, 0, on: cday(2026, 9, 30), enabled: false)
        .nextFireDate(after: date(2026, 9, 30, 12, 0), calendar: shanghai) == nil, "disabled → nil")
}

private func testOneOffIgnoresWeekdays() {
    var r = oneOff(19, 0, on: cday(2026, 9, 30))
    r.weekdays = []
    expect(r.nextFireDate(after: date(2026, 9, 30, 12, 0), calendar: shanghai) == date(2026, 9, 30, 19, 0),
           "weekdays don't apply to a one-off")
}

private func testCanFire() {
    let now = date(2026, 9, 30, 12, 0)
    expect(oneOff(19, 0, on: cday(2026, 9, 30)).canFire(now: now, calendar: shanghai), "future one-off can fire")
    expect(!oneOff(9, 0, on: cday(2026, 9, 30)).canFire(now: now, calendar: shanghai), "past one-off can't")
    expect(DailyReminder(hour: 9, minute: 0).canFire(now: now, calendar: shanghai), "repeating with days can fire")
    expect(!DailyReminder(hour: 9, minute: 0, weekdays: []).canFire(now: now, calendar: shanghai), "no days → can't fire")
}

private func testOneOffDue() {
    let r = oneOff(19, 0, on: cday(2026, 9, 30))
    let due = ReminderSchedule.due(in: [r], from: date(2026, 9, 30, 18, 59), to: date(2026, 9, 30, 19, 0, 1),
                                   grace: 30 * 60, calendar: shanghai)
    expect(due.map(\.reminder.id) == [r.id], "a one-off is due at its time")
}

private func testPrunableOneOffs() {
    let now = date(2026, 9, 30, 19, 5)
    let grace: TimeInterval = 30 * 60
    let justDue = oneOff(19, 0, on: cday(2026, 9, 30))     // within grace, not shown yet
    let shown = oneOff(18, 50, on: cday(2026, 9, 30))      // fired and dismissed
    let stale = oneOff(9, 0, on: cday(2026, 9, 30))        // long past: can never be due again
    let snoozed = oneOff(8, 0, on: cday(2026, 9, 30))
    let showing = oneOff(18, 0, on: cday(2026, 9, 30))
    let future = oneOff(21, 0, on: cday(2026, 9, 30))
    let daily = DailyReminder(hour: 9, minute: 0)
    let all = [justDue, shown, stale, snoozed, showing, future, daily]
    let result = Set(ReminderSchedule.prunableOneOffs(
        in: all, now: now, grace: grace,
        fired: [shown.id, showing.id, snoozed.id], busy: [snoozed.id, showing.id], calendar: shanghai))
    expect(result == [shown.id, stale.id], "prune what fired or can't fire anymore, never what's due, busy or ahead")
    expect(!result.contains(justDue.id), "a due one-off that hasn't been shown survives (sleep / timer tolerance)")
}

private func testOneOffKeepsCalendarDayAcrossTimeZones() {
    // Made in Shanghai for Oct 3 09:00; in New York it's still Oct 3 09:00 local
    let r = oneOff(9, 0, on: cday(2026, 10, 3))
    let ny = calendar("America/New_York")
    expect(r.oneOffDate(calendar: ny) == date(2026, 10, 3, 9, 0, cal: ny), "the day floats with the time zone")
}

private func testDecodesOldData() {
    let json = #"[{"id":"6F1C0B2E-8D1A-4C3B-9E5F-0A1B2C3D4E5F","hour":23,"minute":0,"note":"睡觉","weekdays":[1,2,3,4,5,6,7],"isEnabled":true}]"#
    let decoded = try? JSONDecoder().decode([DailyReminder].self, from: Data(json.utf8))
    expect(decoded?.first?.day == nil && decoded?.first?.note == "睡觉", "reminders saved before one-offs still load")

    let r = oneOff(19, 0, on: cday(2026, 9, 30))
    let back = (try? JSONEncoder().encode([r])).flatMap { try? JSONDecoder().decode([DailyReminder].self, from: $0) }
    expect(back?.first == r, "one-off round-trips")
}

private func testLabels() {
    with(.zh) {
        let now = date(2026, 9, 30, 12, 0)
        expect(oneOff(19, 0, on: cday(2026, 9, 30)).daysSummary(calendar: shanghai) == "仅一次", "summary says once")
        expect(DailyReminder.relativeDayLabel(date(2026, 10, 8, 9, 0), now: now, calendar: shanghai) == "10月8日",
               "a week or more away shows the date")
        expect(DailyReminder.relativeDayLabel(date(2026, 10, 2, 9, 0), now: now, calendar: shanghai) == "周五",
               "within the week shows the weekday")
        expect(oneOff(19, 0, on: cday(2026, 9, 30)).scheduleSummary(now: now, calendar: shanghai) == "今天",
               "one-off schedule is its day")
        expect(DailyReminder(hour: 9, minute: 0).scheduleSummary(now: now, calendar: shanghai) == "每天",
               "repeating schedule is its days")
        let alert = AlertText.reminder(DailyReminder(hour: 19, minute: 0, note: "睡觉", day: cday(2026, 9, 30)),
                                       snoozeCount: 0)
        expect(alert.eyebrow == "19:00 · 提醒", "one-off alert isn't called a daily reminder, got \(alert.eyebrow)")
    }
    with(.en) {
        expect(DailyReminder.relativeDayLabel(date(2026, 10, 8, 9, 0), now: date(2026, 9, 30, 12, 0), calendar: shanghai) == "Oct 8",
               "English date label")
    }
}

// MARK: - Parser

/// (sentence, now, "HH:mm" or nil, fire day or nil for repeating, note)
private let oneOffCases: [(String, Date, String?, CalendarDay?, String)] = [
    // No period word: the nearest of 7:00 / 19:00
    ("7点钟提醒我睡觉", date(2026, 9, 30, 12, 0), "19:00", cday(2026, 9, 30), "睡觉"),
    ("7点钟提醒我睡觉", date(2026, 9, 30, 6, 0), "07:00", cday(2026, 9, 30), "睡觉"),
    ("七点提醒我", date(2026, 9, 30, 20, 0), "07:00", cday(2026, 10, 1), ""),
    ("十一点睡觉", date(2026, 9, 30, 12, 0), "23:00", cday(2026, 9, 30), "睡觉"),
    // Period word: today if still ahead, else tomorrow
    ("晚上10点45分放下手机", date(2026, 9, 30, 12, 0), "22:45", cday(2026, 9, 30), "放下手机"),
    ("晚上10点放下手机", date(2026, 9, 30, 23, 0), "22:00", cday(2026, 10, 1), "放下手机"),
    // A named day
    ("明天下午三点开会", date(2026, 9, 30, 12, 0), "15:00", cday(2026, 10, 1), "开会"),
    ("明晚8点看电影", date(2026, 9, 30, 12, 0), "20:00", cday(2026, 10, 1), "看电影"),
    ("后天早上8点去医院", date(2026, 9, 30, 12, 0), "08:00", cday(2026, 10, 2), "去医院"),
    ("今晚十点给妈妈打电话", date(2026, 9, 30, 12, 0), "22:00", cday(2026, 9, 30), "给妈妈打电话"),
    ("10月3号上午九点出发", date(2026, 9, 30, 12, 0), "09:00", cday(2026, 10, 3), "出发"),
    ("9月1号上午九点交材料", date(2026, 9, 30, 12, 0), "09:00", cday(2027, 9, 1), "交材料"),
    ("下周一上午十点面试", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 5), "面试"),
    ("明天提醒我交作业", date(2026, 9, 30, 12, 0), nil, cday(2026, 10, 1), "交作业"),
    // Repeat words keep it repeating
    ("每天晚上11点提醒我睡觉", date(2026, 9, 30, 12, 0), "23:00", nil, "睡觉"),
    ("工作日早上8点半喝水", date(2026, 9, 30, 12, 0), "08:30", nil, "喝水"),
    ("周末上午十点拉伸一下", date(2026, 9, 30, 12, 0), "10:00", nil, "拉伸一下"),
    ("每周一上午十点开周会", date(2026, 9, 30, 12, 0), "10:00", nil, "开周会"),
    // Nothing to go on: stays a repeating draft without a time
    ("提醒我喝水", date(2026, 9, 30, 12, 0), nil, nil, "喝水"),
]

private func testParserOneOff() {
    for (text, now, time, day, note) in oneOffCases {
        let p = ReminderParser.parse(text, now: now, calendar: shanghai)
        let label = p.hour.map { String(format: "%02d:%02d", $0, p.minute ?? 0) }
        expect(label == time, "\(text): time \(String(describing: label)) ≠ \(String(describing: time))")
        expect(p.day == day, "\(text): day \(String(describing: p.day)) ≠ \(String(describing: day))")
        expect(p.note == note, "\(text): note \"\(p.note)\" ≠ \"\(note)\"")
    }
}

/// (sentence, now, "HH:mm" or nil, day or nil, note, needs a second look)
private let reviewCases: [(String, Date, String?, CalendarDay?, String, Bool)] = [
    // Dates in other shapes
    ("5号上午10点交房租", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 5), "交房租", false),
    ("十月三号上午九点出发", date(2026, 9, 30, 12, 0), "09:00", cday(2026, 10, 3), "出发", false),
    ("下个月3号上午九点出发", date(2026, 9, 30, 12, 0), "09:00", cday(2026, 10, 3), "出发", false),
    ("30号晚上8点交报告", date(2026, 9, 30, 12, 0), "20:00", cday(2026, 9, 30), "交报告", false),
    ("下下周一上午十点复查", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 12), "复查", false),
    ("下周末上午十点去爬山", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 10), "去爬山", false),
    // 号 that isn't a date: building, metro line
    ("下午3点去5号楼开会", date(2026, 9, 30, 12, 0), "15:00", cday(2026, 9, 30), "去5号楼开会", false),
    ("明天下午3点坐2号线去公司", date(2026, 9, 30, 12, 0), "15:00", cday(2026, 10, 1), "坐2号线去公司", false),
    // This month has no 31st: next month's
    ("31号上午十点交房租", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 31), "交房租", false),
    // An unsupported repeat isn't silently made a one-off
    ("每两天上午十点浇花", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 1), "每两天浇花", true),
    // 周 / 月 inside ordinary words aren't date leftovers
    ("明天下午三点交周报", date(2026, 9, 30, 12, 0), "15:00", cday(2026, 10, 1), "交周报", false),
    ("明天早上8点提醒我吃月饼", date(2026, 9, 30, 12, 0), "08:00", cday(2026, 10, 1), "吃月饼", false),
    // A single weekday without 每 is the coming one (2026-09-30 is a Wednesday)
    ("周五下午三点交周报", date(2026, 9, 30, 12, 0), "15:00", cday(2026, 10, 2), "交周报", false),
    ("星期一上午十点面试", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 5), "面试", false),
    ("周三晚上8点开会", date(2026, 9, 30, 12, 0), "20:00", cday(2026, 9, 30), "开会", false),
    ("周三7点开会", date(2026, 9, 30, 12, 0), "19:00", cday(2026, 9, 30), "开会", false),
    ("星期三上午十点开会", date(2026, 9, 30, 12, 0), "10:00", cday(2026, 10, 7), "开会", false),
    // Several days, a range or 每 still repeat
    ("周二和周四晚上8点练琴", date(2026, 9, 30, 12, 0), "20:00", nil, "练琴", false),
    ("周一到周五早上八点半打卡", date(2026, 9, 30, 12, 0), "08:30", nil, "打卡", false),
    ("每周五下午三点交周报", date(2026, 9, 30, 12, 0), "15:00", nil, "交周报", false),
    // Impossible date: not turned into another date; the leftover asks for a second look
    ("2月30号上午九点交材料", date(2026, 9, 30, 12, 0), "09:00", cday(2026, 10, 1), "2月30号交材料", true),
    // Midnight at the end of an evening
    ("明晚12点提醒我睡觉", date(2026, 9, 30, 22, 0), "00:00", cday(2026, 10, 2), "睡觉", false),
    ("今晚12点提醒我睡觉", date(2026, 9, 30, 22, 0), "00:00", cday(2026, 10, 1), "睡觉", false),
    // The period can come before the reminder words
    ("今晚提醒我8点吃药", date(2026, 9, 30, 7, 0), "20:00", cday(2026, 9, 30), "吃药", false),
    ("明晚提醒我8点吃药", date(2026, 9, 30, 7, 0), "20:00", cday(2026, 10, 1), "吃药", false),
    // 每 / 天天 only count as repeat words
    ("明天下午三点提醒我给每个人发邮件", date(2026, 9, 30, 12, 0), "15:00", cday(2026, 10, 1), "给每个人发邮件", false),
    ("今天天黑前六点提醒我收衣服", date(2026, 9, 30, 12, 0), "18:00", cday(2026, 9, 30), "天黑前收衣服", false),
]

private func testParserReviewCases() {
    for (text, now, time, day, note, unclear) in reviewCases {
        let p = ReminderParser.parse(text, now: now, calendar: shanghai)
        let label = p.hour.map { String(format: "%02d:%02d", $0, p.minute ?? 0) }
        expect(label == time, "\(text): time \(String(describing: label)) ≠ \(String(describing: time))")
        expect(p.day == day, "\(text): day \(String(describing: p.day)) ≠ \(String(describing: day))")
        expect(p.note == note, "\(text): note \"\(p.note)\" ≠ \"\(note)\"")
        expect(p.isUnclear == unclear, "\(text): unclear \(p.isUnclear) ≠ \(unclear)")
    }
}

private func testClockTimeIsNotCountdown() {
    guard case .daily(let p) = ReminderParser.parseCommand("7点钟提醒我睡觉", now: date(2026, 9, 30, 12, 0), calendar: shanghai) else {
        expect(false, "a clock time is a reminder, not a countdown")
        return
    }
    expect(p.isOneOff, "and it's a one-off")
}

let oneOffTests: [(String, () -> Void)] = [
    ("oneOffFiresOnce", testOneOffFiresOnce),
    ("oneOffIgnoresWeekdays", testOneOffIgnoresWeekdays),
    ("oneOffCanFire", testCanFire),
    ("oneOffDue", testOneOffDue),
    ("oneOffPrunable", testPrunableOneOffs),
    ("oneOffTimeZone", testOneOffKeepsCalendarDayAcrossTimeZones),
    ("parserReviewCases", testParserReviewCases),
    ("oneOffDecodesOldData", testDecodesOldData),
    ("oneOffLabels", testLabels),
    ("parserOneOff", testParserOneOff),
    ("parserClockTimeIsNotCountdown", testClockTimeIsNotCountdown),
]
