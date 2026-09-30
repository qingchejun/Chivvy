import Foundation


private func testPicksLanguage() {
    with(.zh) { expect(L("开始", "Start") == "开始", "zh picks the Chinese string") }
    with(.en) { expect(L("开始", "Start") == "Start", "en picks the English string") }
}

private func testDaysSummaryEnglish() {
    with(.en) {
        func summary(_ days: Set<Int>) -> String {
            DailyReminder(hour: 23, minute: 0, weekdays: days).daysSummary(calendar: shanghai)
        }
        expect(summary(DailyReminder.everyDay) == "Every day", "every day")
        expect(summary(DailyReminder.weekdaysOnly) == "Weekdays", "weekdays")
        expect(summary(DailyReminder.weekendsOnly) == "Weekends", "weekends")
        expect(summary([]) == "Never", "no days")
        // shanghai uses the gregorian default (week starts Sunday)
        expect(summary([6, 2, 4]) == "Mon Wed Fri", "listed days, got \(summary([6, 2, 4]))")
        expect(summary([1, 3]) == "Sun Tue", "Sunday first, got \(summary([1, 3]))")
    }
}

private func testWeekdayNames() {
    with(.zh) {
        expect(DailyReminder.shortName(weekday: 1) == "周日", "zh Sunday")
        expect(DailyReminder.letter(weekday: 7) == "六", "zh Saturday letter")
    }
    with(.en) {
        expect(DailyReminder.shortName(weekday: 7) == "Sat", "en Saturday")
        expect(DailyReminder.letter(weekday: 2) == "M", "en Monday letter")
    }
}

private func testPresetLabels() {
    let chineseDefault = TimerPreset(label: "25 分钟", minutes: 25)
    let englishDefault = TimerPreset(label: "25 min", minutes: 25)
    let custom = TimerPreset(label: "番茄", minutes: 25)
    // A default label whose number no longer matches the minutes was edited by hand
    let edited = TimerPreset(label: "5 分钟", minutes: 7)

    with(.en) {
        expect(chineseDefault.displayLabel == "25 min", "saved Chinese default shows in English")
        expect(englishDefault.displayLabel == "25 min", "English default stays")
        expect(custom.displayLabel == "番茄", "user-typed name is kept")
        expect(edited.displayLabel == "5 分钟", "mismatched label is treated as custom")
        expect(TimerPreset.builtIn.map(\.label) == ["5 min", "10 min", "15 min", "25 min"], "built-ins in English")
    }
    with(.zh) {
        expect(englishDefault.displayLabel == "25 分钟", "saved English default shows in Chinese")
        expect(custom.displayLabel == "番茄", "user-typed name is kept")
        expect(TimerPreset.builtIn.first?.label == "5 分钟", "built-ins in Chinese")
    }
}

private func testDefaultIsSettledOnce() {
    let defaults = UserDefaults.standard
    let keys = [L10n.key, "dailyReminders", "customPresets", "hasShownBackgroundTip"]
    let saved = keys.map { defaults.object(forKey: $0) }
    keys.forEach(defaults.removeObject(forKey:))

    let first = L10n.current
    expect(first == L10n.defaultLanguage, "fresh install follows the system language")
    expect(defaults.string(forKey: L10n.key) == first.rawValue, "the default is saved on first read")
    // Closing the main window writes this key; it must not turn a new user's UI Chinese later
    defaults.set(true, forKey: "hasShownBackgroundTip")
    expect(L10n.current == first, "later writes don't change the language")

    // An upgrade from 2.0 (reminders saved, no language yet) keeps Chinese
    defaults.removeObject(forKey: L10n.key)
    expect(L10n.current == .zh, "upgrading users keep Chinese")

    for (key, value) in zip(keys, saved) { defaults.set(value, forKey: key) }
}

let localizationTests: [(String, () -> Void)] = [
    ("localizationPicksLanguage", testPicksLanguage),
    ("localizationDaysSummaryEnglish", testDaysSummaryEnglish),
    ("localizationWeekdayNames", testWeekdayNames),
    ("localizationPresetLabels", testPresetLabels),
    ("localizationDefaultSettledOnce", testDefaultIsSettledOnce),
]
