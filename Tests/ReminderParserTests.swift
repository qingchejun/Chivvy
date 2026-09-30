import Foundation

/// (sentence, "HH:mm" or nil, weekdays, note)
private let cases: [(String, String?, Set<Int>, String)] = [
    // Time of day + filler words
    ("每天晚上11点提醒我睡觉", "23:00", DailyReminder.everyDay, "睡觉"),
    ("每天晚上十一点半提醒我洗漱", "23:30", DailyReminder.everyDay, "洗漱"),
    ("晚上10点45分放下手机", "22:45", DailyReminder.everyDay, "放下手机"),
    ("每天22:30洗漱", "22:30", DailyReminder.everyDay, "洗漱"),
    ("每天22：30洗漱", "22:30", DailyReminder.everyDay, "洗漱"),
    ("每天中午12点吃饭", "12:00", DailyReminder.everyDay, "吃饭"),
    ("中午一点半午休", "13:30", DailyReminder.everyDay, "午休"),
    ("下午三点一刻喝水", "15:15", DailyReminder.everyDay, "喝水"),
    ("每天凌晨1点必须睡觉", "01:00", DailyReminder.everyDay, "必须睡觉"),
    ("凌晨十二点关电脑", "00:00", DailyReminder.everyDay, "关电脑"),
    ("晚上十二点睡觉", "00:00", DailyReminder.everyDay, "睡觉"),
    ("早上七点二十起床", "07:20", DailyReminder.everyDay, "起床"),
    ("晚上八点零五分吃药", "20:05", DailyReminder.everyDay, "吃药"),
    ("两点喝水", "02:00", DailyReminder.everyDay, "喝水"),
    // No period word: keep the literal hour, the confirm card lets the user fix it
    ("提醒我十一点睡觉", "11:00", DailyReminder.everyDay, "睡觉"),
    ("叫我9点开会", "09:00", DailyReminder.everyDay, "开会"),
    // Repeat rules
    ("工作日早上8点半喝水", "08:30", DailyReminder.weekdaysOnly, "喝水"),
    ("周一到周五早上八点半打卡", "08:30", DailyReminder.weekdaysOnly, "打卡"),
    ("周末上午十点拉伸一下", "10:00", DailyReminder.weekendsOnly, "拉伸一下"),
    ("每周一三五晚上九点去跑步", "21:00", [2, 4, 6], "去跑步"),
    ("每周二和周四晚上8点练琴", "20:00", [3, 5], "练琴"),
    ("星期六、星期天早上9点爬山", "09:00", [7, 1], "爬山"),
    ("每周日晚上十点复盘", "22:00", [1], "复盘"),
    // Punctuation, polite words, the app name
    ("Tick，每天晚上11点，提醒我：该睡觉了。", "23:00", DailyReminder.everyDay, "该睡觉了"),
    ("帮我设置一个每天晚上11点的提醒，早点睡", "23:00", DailyReminder.everyDay, "早点睡"),
    // No time at all
    ("提醒我喝水", nil, DailyReminder.everyDay, "喝水"),
]

private func label(_ p: ParsedReminder) -> String? {
    guard let h = p.hour, let m = p.minute else { return nil }
    return String(format: "%02d:%02d", h, m)
}

private func testSentences() {
    for (text, time, days, note) in cases {
        let p = ReminderParser.parse(text)
        expect(label(p) == time, "\(text): time \(String(describing: label(p))) ≠ \(String(describing: time))")
        expect(p.weekdays == days, "\(text): days \(p.weekdays.sorted()) ≠ \(days.sorted())")
        expect(p.note == note, "\(text): note \"\(p.note)\" ≠ \"\(note)\"")
        expect(!p.isOneOff, "\(text): not one-off")
    }
}

private func testOneOff() {
    for text in ["明天下午三点开会", "今晚十点给妈妈打电话", "后天早上8点去医院", "10月3号上午九点出发", "下周一上午十点面试"] {
        expect(ReminderParser.parse(text).isOneOff, "\(text): one-off")
    }
    // "每" wins: a repeating reminder that mentions a weekday is not one-off
    expect(!ReminderParser.parse("每周一上午十点开周会").isOneOff, "每周一 is repeating")
}

private func testDateWithoutTime() {
    // The date detector alone would invent 12:00 for "明天"; no time was said, so leave it empty
    let p = ReminderParser.parse("明天提醒我交作业")
    expect(p.hour == nil, "no time said → hour stays nil, got \(String(describing: p.hour))")
}

private func testEmpty() {
    let p = ReminderParser.parse("  ")
    expect(p.hour == nil && p.note.isEmpty, "blank input parses to nothing")
}

// MARK: - Countdown vs. daily reminder

/// (sentence, seconds, note)
private let countdownCases: [(String, Int, String)] = [
    ("一分钟后提醒我睡觉", 60, "睡觉"),
    ("5分钟后提醒我关火", 300, "关火"),
    ("10分钟以后喝水", 600, "喝水"),
    ("十五分钟之后叫我", 900, ""),
    ("半小时后叫我起来", 1800, "起来"),
    ("一个半小时后提醒我出门", 5400, "出门"),
    ("两小时后提醒我休息", 7200, "休息"),
    ("1小时20分钟后开会", 4800, "开会"),
    ("一分半钟后关火", 90, "关火"),
    ("三十秒后提醒我", 30, ""),
    ("倒计时25分钟", 1500, ""),
    ("25分钟倒计时，写作业", 1500, "写作业"),
    ("计时十分钟 泡面", 600, "泡面"),
    // Real recognizer output: punctuation, decimals, 百
    ("一分钟后，提醒我睡觉。", 60, "睡觉"),
    ("倒计时，25分钟。", 1500, ""),
    ("1.5小时后提醒我休息", 5400, "休息"),
    ("一百分钟后提醒我", 6000, ""),
    ("一百二十分钟后收衣服", 7200, "收衣服"),
]

private func testCountdowns() {
    for (text, seconds, note) in countdownCases {
        guard case .countdown(let s, let n) = ReminderParser.parseCommand(text) else {
            expect(false, "\(text): should be a countdown")
            continue
        }
        expect(s == seconds, "\(text): \(s)s ≠ \(seconds)s")
        expect(n == note, "\(text): note \"\(n)\" ≠ \"\(note)\"")
    }
}

private func testDailyStaysDaily() {
    for text in ["每天晚上十一点提醒我睡觉", "晚上10点45分放下手机", "每天晚上十一点半提醒我洗漱",
                 "工作日早上8点半喝水", "提醒我喝水",
                 // "10分" belongs to the clock time, not a duration
                 "下午3点10分以后提醒我开会", "晚上八点二十分以后别喝咖啡"] {
        guard case .daily = ReminderParser.parseCommand(text) else {
            expect(false, "\(text): should be a daily reminder")
            continue
        }
        expect(true, "")
    }
}

let parserTests: [(String, () -> Void)] = [
    ("parserCountdowns", testCountdowns),
    ("parserDailyStaysDaily", testDailyStaysDaily),
    ("parserSentences", testSentences),
    ("parserOneOff", testOneOff),
    ("parserEmpty", testEmpty),
    ("parserDateWithoutTime", testDateWithoutTime),
]
