import Foundation

private func testDurationLabel() {
    with(.zh) {
        expect(durationLabel(600) == "10 分钟", "zh minutes, got \(durationLabel(600))")
        expect(durationLabel(3_690) == "1 小时 1 分钟 30 秒", "zh mixed, got \(durationLabel(3_690))")
        expect(durationLabel(45) == "45 秒", "zh seconds only")
    }
    with(.en) {
        expect(durationLabel(600) == "10 min", "en minutes")
        expect(durationLabel(7_200) == "2 hr", "en hours")
    }
}

private func testMainSectionPersistence() {
    let defaults = UserDefaults(suiteName: "ChivvyTests.mainSection")!
    defaults.removePersistentDomain(forName: "ChivvyTests.mainSection")
    expect(MainSection.saved(in: defaults) == .timer, "defaults to the timer")
    MainSection.reminders.save(in: defaults)
    expect(MainSection.saved(in: defaults) == .reminders, "remembers the last section")
    defaults.set("bogus", forKey: MainSection.key)
    expect(MainSection.saved(in: defaults) == .timer, "unknown value falls back to the timer")
    defaults.removePersistentDomain(forName: "ChivvyTests.mainSection")
}

private func testReminderAlertText() {
    with(.zh) {
        let water = DailyReminder(hour: 8, minute: 30, note: "喝水")
        let onTime = AlertText.reminder(water, snoozeCount: 0)
        expect(onTime.eyebrow == "08:30 · 每日提醒", "eyebrow, got \(onTime.eyebrow)")
        expect(onTime.title == "喝水", "the note is the headline")
        expect(onTime.snooze == nil, "no snooze line on time")

        let snoozed = AlertText.reminder(water, snoozeCount: 1)
        expect(snoozed.snooze?.used == 1, "one snooze used")
        expect(snoozed.snooze?.text == "已推迟 1 次，还能推迟 2 次", "got \(snoozed.snooze?.text ?? "nil")")
        expect(snoozed.snooze?.exhausted == false, "can still snooze")

        let done = AlertText.reminder(water, snoozeCount: SnoozeState.maxCount)
        expect(done.snooze?.exhausted == true, "snoozes used up")
        expect(done.snooze?.text == "已推迟 3 次，不能再推迟了", "got \(done.snooze?.text ?? "nil")")

        let blank = AlertText.reminder(DailyReminder(hour: 23, minute: 0), snoozeCount: 0)
        expect(blank.title == "23:00 到了", "no note: the time becomes the headline, got \(blank.title)")
        expect(blank.eyebrow == "每日提醒", "and the eyebrow drops the time, got \(blank.eyebrow)")
    }
    with(.en) {
        let text = AlertText.reminder(DailyReminder(hour: 21, minute: 30, note: "Laptop off"), snoozeCount: 2)
        expect(text.eyebrow == "21:30 · Daily reminder", "en eyebrow, got \(text.eyebrow)")
        expect(text.snooze?.text == "Snoozed 2 times · 1 left", "en snooze, got \(text.snooze?.text ?? "nil")")
        let once = AlertText.reminder(DailyReminder(hour: 21, minute: 30), snoozeCount: 1)
        expect(once.snooze?.text == "Snoozed once · 2 left", "en singular, got \(once.snooze?.text ?? "nil")")
    }
}

private func testTimerAlertText() {
    with(.zh) {
        let text = AlertText.timer(note: "关火", seconds: 600)
        expect(text.eyebrow == "10 分钟倒计时结束", "got \(text.eyebrow)")
        expect(text.title == "关火", "the note is the headline")
        expect(AlertText.timer(note: "", seconds: 600).title == "时间到", "no note")
    }
    with(.en) {
        expect(AlertText.timer(note: "", seconds: 90).eyebrow == "1 min 30 sec countdown done", "en eyebrow")
        expect(AlertText.timer(note: "", seconds: 90).title == "Time's up", "en title")
    }
}

private func testWhenLabel() {
    let now = date(2026, 10, 1, 21, 17)
    with(.zh) {
        expect(DailyReminder.whenLabel(date(2026, 10, 1, 21, 30), now: now, calendar: shanghai) == "13 分钟后", "soon")
        expect(DailyReminder.whenLabel(date(2026, 10, 1, 21, 17, 30), now: now, calendar: shanghai) == "1 分钟后", "under a minute rounds up")
        expect(DailyReminder.whenLabel(date(2026, 10, 1, 23, 0), now: now, calendar: shanghai) == "今天", "later today")
        expect(DailyReminder.whenLabel(date(2026, 10, 2, 8, 30), now: now, calendar: shanghai) == "明天", "tomorrow")
        // 2026-10-04 is a Sunday
        expect(DailyReminder.whenLabel(date(2026, 10, 4, 8, 30), now: now, calendar: shanghai) == "周日", "later this week")
    }
    with(.en) {
        expect(DailyReminder.whenLabel(date(2026, 10, 1, 21, 30), now: now, calendar: shanghai) == "in 13 min", "en soon")
    }
}

private func testPresetShortLabel() {
    with(.zh) {
        expect(TimerPreset(label: "10 分钟", minutes: 10).shortLabel == "10 分", "zh default shortens")
        expect(TimerPreset(label: "10 min", minutes: 10).shortLabel == "10 分", "en default shown in zh")
        expect(TimerPreset(label: "番茄", minutes: 25).shortLabel == "番茄", "custom name kept")
    }
    with(.en) {
        expect(TimerPreset(label: "10 分钟", minutes: 10).shortLabel == "10m", "en default shortens")
    }
}

let uiModelTests: [(String, () -> Void)] = [
    ("duration label", testDurationLabel),
    ("main section persistence", testMainSectionPersistence),
    ("reminder alert text", testReminderAlertText),
    ("timer alert text", testTimerAlertText),
    ("when label", testWhenLabel),
    ("preset short label", testPresetShortLabel),
]
