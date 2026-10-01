import Foundation

/// What a spoken / typed sentence like "每天晚上十一点提醒我睡觉" means as a reminder
struct ParsedReminder: Equatable {
    var hour: Int?
    var minute: Int?
    var weekdays: Set<Int>
    var note: String
    /// A one-time reminder ("7点钟提醒我睡觉", "明天下午三点开会"): the day it fires.
    /// nil = repeating on `weekdays`.
    var day: CalendarDay?
    /// Something date-like was left over ("2月30号", "下下下周"), so the result deserves a second look
    var isUnclear = false

    var isOneOff: Bool { day != nil }
}

/// What a voice sentence asks for
enum VoiceCommand: Equatable {
    /// "一分钟后提醒我睡觉", "倒计时25分钟"
    case countdown(seconds: Int, note: String)
    /// "每天晚上十一点提醒我睡觉" (repeating) or "7点钟提醒我睡觉" (one-off)
    case daily(ParsedReminder)
}

/// Rule-based parser for short Chinese reminder sentences.
/// Order matters: repeat rules are cut out first, then the time, and what's left is the note.
enum ReminderParser {
    /// Relative durations ("X分钟后") mean a countdown; everything else is a reminder
    static func parseCommand(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> VoiceCommand {
        var text = normalize(input)
        if let seconds = extractCountdown(&text) {
            return .countdown(seconds: seconds, note: cleanNote(text))
        }
        return .daily(parse(input, now: now, calendar: calendar))
    }

    /// Repeating only when the sentence says so ("每天", "工作日", "周一三五"…);
    /// otherwise a time means one time, at the nearest such moment
    static func parse(_ input: String, now: Date = Date(), calendar: Calendar = .current) -> ParsedReminder {
        var text = normalize(input)
        let saysEvery = matches(repeatWordPattern, in: text)

        let named = saysEvery ? nil : extractDay(&text, now: now, calendar: calendar)
        let (weekdays, saysDays) = extractWeekdays(&text)
        var time = extractTime(&text) ?? extractTimeWithDetector(&text, calendar: calendar)
        // "明晚提醒我…" without a time: the period word wasn't consumed by the time
        while remove(#"今晚|明晚|今早|明早"#, from: &text) != nil {}
        // "今晚提醒我8点": the period came with the day, not the time
        if let t = time, t.period == nil, let implied = named?.period {
            time = ClockTime(hour: adjust(hour: t.hour, period: implied), minute: t.minute, period: implied)
        }

        var hour = time?.hour
        var day: Date?
        if let start = named?.day {
            day = start
            if let time {
                // "今天7点" at noon is 19:00; on another day the hour is taken as said
                if !time.hasPeriod, calendar.isDate(start, inSameDayAs: now) {
                    hour = nearest(time, now: now, calendar: calendar, todayOnly: true).hour
                }
                // "明晚12点" is the midnight that ends tomorrow evening
                if time.hour == 0, let period = time.period, eveningPeriods.contains(period) {
                    day = calendar.date(byAdding: .day, value: 1, to: start)
                }
            }
        } else if !saysEvery, !saysDays, let time {
            (hour, day) = nearest(time, now: now, calendar: calendar, todayOnly: false)
        }
        // "星期三上午十点" said on a Wednesday afternoon means next Wednesday
        if named?.rollsToNextWeek == true, let start = day, let hour,
           let fire = calendar.date(bySettingHour: hour, minute: time?.minute ?? 0, second: 0, of: start), fire <= now {
            day = calendar.date(byAdding: .day, value: 7, to: start)
        }

        let note = cleanNote(text)
        let leftover = matches(leftoverDatePattern, in: note)
        return ParsedReminder(
            hour: hour,
            minute: time?.minute,
            weekdays: weekdays,
            note: note,
            day: day.map { CalendarDay($0, calendar: calendar) },
            isUnclear: day != nil && ((named?.isInvalid ?? false) || leftover)
        )
    }

    /// Date-like words still in the note: a date or repeat we didn't understand ("2月30号", "每两天"),
    /// or a second day phrase that lost to the first
    private static let leftoverDatePattern =
        "(?:\(dayNumber))(?:日|号\(notADateSuffix)|月)|下下|(?:周|星期|礼拜)[一二三四五六日天]"
        + "|今天|明天|后天|今晚|明晚|今早|明早|每[0-9两一二三四五六七八九十隔]"

    /// 每 or 天天 as repeat words, not inside "每个人" or "今天天黑"
    private static let repeatWordPattern =
        #"每(天|日|晚|早|周|个?星期|个?礼拜|个?工作日|个?周末|个?月)|(?<![今明后])天天"#
    private static let eveningPeriods: Set<String> = ["晚上", "夜里", "夜晚", "半夜", "今晚", "明晚"]

    /// The next moment matching the time: "7点" without 早上/晚上 could be 7:00 or 19:00, whichever comes first.
    /// `todayOnly` keeps the day fixed and falls back to the hour as said.
    private static func nearest(_ time: ClockTime, now: Date, calendar: Calendar,
                                todayOnly: Bool) -> (hour: Int, day: Date) {
        let hours = !time.hasPeriod && (1..<12).contains(time.hour) ? [time.hour, time.hour + 12] : [time.hour]
        let today = calendar.startOfDay(for: now)
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today) ?? today
        let options: [(hour: Int, day: Date, fire: Date)] = hours.flatMap { hour in
            (todayOnly ? [today] : [today, tomorrow]).compactMap { day in
                calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: day).map { (hour, day, $0) }
            }
        }
        let next = options.filter { $0.fire > now }.min { $0.fire < $1.fire }
        return next.map { ($0.hour, $0.day) } ?? (time.hour, today)
    }

    // MARK: - Normalize

    private static func normalize(_ input: String) -> String {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        // The app name, current and old, isn't part of the note
        text = text.replacingOccurrences(of: "chivvy|tick", with: "", options: [.regularExpression, .caseInsensitive])
        text = text.replacingOccurrences(of: "：", with: ":")
        // "每晚十一点" carries the period inside the repeat word
        text = text.replacingOccurrences(of: "每晚", with: "每天晚上")
        text = text.replacingOccurrences(of: "每早", with: "每天早上")
        return text
    }

    // MARK: - Named day

    private struct NamedDay {
        /// Start of the day; nil when the phrase isn't a real date ("2月30号")
        var day: Date?
        /// 今晚 / 明早 also say which half of the day
        var period: String?
        var isInvalid = false
        /// A bare weekday that's today: next week's if the time has already passed
        var rollsToNextWeek = false
    }

    /// Weeks run Monday to Sunday: index 0 = Monday
    private static let weekdayIndex: [String: Int] = ["一": 0, "二": 1, "三": 2, "四": 3, "五": 4, "六": 5, "日": 6, "天": 6]

    private static let dayNumber = "[0-9]{1,2}|[一二三四五六七八九十]{1,3}"
    /// "5号楼", "2号线": 号 as a number, not a date
    private static let notADateSuffix = "(?![线楼门房室栋座位床码])"

    /// "明天", "10月3号", "5号", "下周一", "下周末"… The words are removed, except 今晚 / 明早 and the like,
    /// which the time pattern still needs for the period.
    private static func extractDay(_ text: inout String, now: Date, calendar: Calendar) -> NamedDay? {
        let today = calendar.startOfDay(for: now)
        func offset(_ days: Int) -> Date? { calendar.date(byAdding: .day, value: days, to: today) }

        // "10月3号", "十月三号", "下个月3号", "5号"
        if let match = firstMatch("(?:(下个?月)|(\(dayNumber))月)?(\(dayNumber))(?:日|号\(notADateSuffix))", in: text),
           let dayOfMonth = match.groups[2].flatMap(chineseNumber) {
            let now = calendar.dateComponents([.year, .month, .day], from: now)
            var year = now.year ?? 2001
            var month = now.month ?? 1
            if match.groups[0] != nil {
                month += 1
            } else if let named = match.groups[1].flatMap(chineseNumber) {
                // A month already gone this year means next year
                if named < month || (named == month && dayOfMonth < now.day ?? 1) { year += 1 }
                month = named
            } else if dayOfMonth < now.day ?? 1 {
                // "5号" on the 30th is next month's 5th
                month += 1
            }
            if month > 12 { year += 1; month -= 12 }
            // Lenient calendars turn 2月30号 into March 2; only accept a date that exists.
            // A bare "31号" in a 30-day month means the next month that has one.
            let saysMonth = match.groups[0] != nil || match.groups[1] != nil
            for extra in 0...(saysMonth ? 0 : 2) {
                guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
                      let monthStart = calendar.date(byAdding: .month, value: extra, to: first) else { break }
                var parts = calendar.dateComponents([.year, .month], from: monthStart)
                parts.day = dayOfMonth
                if let date = calendar.date(from: parts), calendar.component(.day, from: date) == dayOfMonth {
                    text.removeSubrange(match.range)
                    return NamedDay(day: date)
                }
            }
            return NamedDay(day: nil, isInvalid: true)
        }

        // Weeks run Monday to Sunday: index 0 = Monday
        let current = (calendar.component(.weekday, from: now) + 5) % 7
        func weeksAhead(_ which: String) -> Int { which == "下下" ? 2 : which.hasPrefix("下") ? 1 : 0 }

        if let match = firstMatch(#"(下下|下个?|这个?|本)周末"#, in: text), let which = match.groups[0] {
            text.removeSubrange(match.range)
            return NamedDay(day: offset(5 - current + 7 * weeksAhead(which)))
        }
        if let match = firstMatch(#"(下下|下个?|这个?|本)(?:周|星期|礼拜)([一二三四五六日天])"#, in: text),
           let which = match.groups[0], let name = match.groups[1] {
            text.removeSubrange(match.range)
            let target = weekdayIndex[name] ?? 0
            return NamedDay(day: offset(target - current + 7 * weeksAhead(which)))
        }
        // A single bare weekday ("周五下午三点") is the coming one. Not 每周五, and not part of a list or range
        // ("周二和周四", "周一到周五"), which repeat.
        if let match = firstMatch(#"(?<![每下这本个、,，和及与到至~-])(?:周|星期|礼拜)([一二三四五六日天])(?![一二三四五六日天、,，和及与到至~-]|周|星期|礼拜)"#, in: text),
           let name = match.groups[0] {
            text.removeSubrange(match.range)
            let target = weekdayIndex[name] ?? 0
            return NamedDay(day: offset((target - current + 7) % 7), rollsToNextWeek: true)
        }

        for (pattern, days) in [("大后天", 3), ("后天", 2), ("明天", 1), ("今天", 0)] where remove(pattern, from: &text) != nil {
            return NamedDay(day: offset(days))
        }
        if let match = firstMatch(#"(今|明)(晚|早)"#, in: text) {
            return NamedDay(day: offset(match.groups[0] == "明" ? 1 : 0),
                            period: match.groups[1] == "晚" ? "晚上" : "早上")
        }
        return nil
    }

    // MARK: - Repeat rules

    private static let weekdayRangePattern =
        #"(每个?)?工作日|(每)?(周|星期|礼拜)一(到|至|-|~)(周|星期|礼拜)?五"#
    private static let weekendPattern = #"(每个?)?周末"#
    /// "每周一三五", "周二和周四", "星期六、星期天"
    private static let weekdayListPattern =
        #"(每个?)?(周|星期|礼拜)[一二三四五六日天](([、,，和及与]|和|及)?(周|星期|礼拜)?[一二三四五六日天])*"#
    private static let everyDayPattern = #"每天|每日|天天"#

    /// The days, and whether the sentence named any (no days named = every day, if repeating at all)
    private static func extractWeekdays(_ text: inout String) -> (Set<Int>, named: Bool) {
        if remove(weekdayRangePattern, from: &text) != nil {
            return (DailyReminder.weekdaysOnly, true)
        }
        if remove(weekendPattern, from: &text) != nil {
            return (DailyReminder.weekendsOnly, true)
        }
        if let phrase = remove(weekdayListPattern, from: &text) {
            // Drop the prefixes so "星期" / "礼拜" / "周" don't contribute characters
            let digits = phrase
                .replacingOccurrences(of: "星期", with: "")
                .replacingOccurrences(of: "礼拜", with: "")
                .replacingOccurrences(of: "周", with: "")
            let map: [Character: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
            let days = Set(digits.compactMap { map[$0] })
            if !days.isEmpty { return (days, true) }
        }
        _ = remove(everyDayPattern, from: &text)
        return (DailyReminder.everyDay, false)
    }

    // MARK: - Countdown

    private static let durationNumber = "[0-9]+(?:\\.[0-9]+)?|[零〇一二两三四五六七八九十百]+"
    private static let durationPattern =
        // Not right after a clock time or another number: "3点10分以后" is 15:10, not "10 minutes later".
        // "计时10分钟" is fine though, hence the separate 时 check.
        "(?<![点:0-9.零〇一二两三四五六七八九十百])(?<![^计]时)"
        + "(?:(?<h>\(durationNumber)|半)个?(?<hh>半)?(?:小时|钟头))?"
        + "(?:(?<m>\(durationNumber))(?:分钟|分)(?<mh>半)?钟?)?"
        + "(?:(?<s>\(durationNumber))(?:秒钟|秒))?"

    /// The recognizer inserts punctuation: "倒计时，25分钟。"
    private static let gap = "[\\s，,。：:、]*"

    /// "X分钟后" / "倒计时X分钟" / "X分钟倒计时"
    private static let countdownPatterns = [
        "\(durationPattern)(?:以后|之后|后)",
        "(?:倒计时|计时)\(gap)\(durationPattern)",
        "\(durationPattern)\(gap)倒计时",
    ]

    private static func extractCountdown(_ text: inout String) -> Int? {
        for pattern in countdownPatterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(text.startIndex..., in: text)
            for match in regex.matches(in: text, range: range) {
                func group(_ name: String) -> String? {
                    Range(match.range(withName: name), in: text).map { String(text[$0]) }
                }
                func value(_ raw: String) -> Double { Double(raw) ?? chineseNumber(raw).map(Double.init) ?? 0 }
                var total = 0.0
                if let h = group("h") {
                    total += h == "半" ? 1800 : value(h) * 3600
                }
                if group("hh") != nil { total += 1800 }
                if let m = group("m") { total += value(m) * 60 }
                if group("mh") != nil { total += 30 }
                if let s = group("s") { total += value(s) }
                let seconds = Int(total.rounded())

                // The all-optional duration can match empty text (e.g. a bare "后")
                guard seconds > 0, let whole = Range(match.range, in: text) else { continue }
                text.removeSubrange(whole)
                return seconds
            }
        }
        return nil
    }

    // MARK: - Time

    private static let number = "[0-9]{1,2}|[零〇一二两三四五六七八九十]{1,3}"
    private static let timePattern =
        "(凌晨|早上|早晨|清晨|上午|中午|下午|傍晚|晚上|夜里|夜晚|半夜|今晚|明晚|今早|明早)?"
        + "(\(number))"
        + "(?::([0-9]{2})|[点时](?:(半)|(一刻)|(三刻)|(\(number))分?)?钟?)"

    private struct ClockTime {
        let hour: Int
        let minute: Int
        /// 早上 / 晚上 / …, as said
        let period: String?

        /// Not ambiguous between morning and evening
        var hasPeriod: Bool { period != nil || hour >= 12 }
    }

    private static func extractTime(_ text: inout String) -> ClockTime? {
        guard let regex = try? NSRegularExpression(pattern: timePattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }

        func group(_ i: Int) -> String? {
            guard let range = Range(match.range(at: i), in: text) else { return nil }
            return String(text[range])
        }

        guard let rawHour = group(2).flatMap(chineseNumber) else { return nil }
        var minute = 0
        if let colonMinutes = group(3) { minute = Int(colonMinutes) ?? 0 }
        else if group(4) != nil { minute = 30 }
        else if group(5) != nil { minute = 15 }
        else if group(6) != nil { minute = 45 }
        else if let m = group(7).flatMap(chineseNumber) { minute = m }

        let period = group(1)
        let hour = adjust(hour: rawHour, period: period)
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }

        if let range = Range(match.range, in: text) {
            text.removeSubrange(range)
        }
        return ClockTime(hour: hour, minute: minute, period: period)
    }

    private static func adjust(hour: Int, period: String?) -> Int {
        switch period {
        case "下午", "傍晚", "晚上", "夜里", "夜晚", "今晚", "明晚":
            // 晚上十二点 = midnight
            return hour == 12 ? 0 : (hour < 12 ? hour + 12 : hour)
        case "中午":
            // 中午一点 = 13:00, 中午十二点 = 12:00
            return hour <= 3 ? hour + 12 : hour
        case "凌晨", "半夜":
            return hour == 12 ? 0 : hour
        default:
            return hour
        }
    }

    /// Fallback for phrasings the rules don't cover
    private static func extractTimeWithDetector(_ text: inout String, calendar: Calendar) -> ClockTime? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date,
              let range = Range(match.range, in: text),
              // "明天" alone is a date without a time; the detector would make it 12:00
              text[range].range(of: "点|时|:|分|am|pm", options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        text.removeSubrange(range)
        // The detector already settled morning vs. evening
        return ClockTime(hour: parts.hour ?? 0, minute: parts.minute ?? 0, period: "")
    }

    /// "11", "十一", "二十", "零五", "两", "一百二十" → Int
    static func chineseNumber(_ raw: String) -> Int? {
        if let n = Int(raw) { return n }
        if let hundredIndex = raw.firstIndex(of: "百") {
            let before = String(raw[..<hundredIndex])
            var after = String(raw[raw.index(after: hundredIndex)...])
            guard let hundreds = before.isEmpty ? 1 : chineseNumber(before), hundreds < 10 else { return nil }
            if after.isEmpty { return hundreds * 100 }
            // "一百五" = 150, "一百零五" = 105
            if after.count == 1, after != "十", !after.hasPrefix("零") { after += "十" }
            guard let rest = chineseNumber(after) else { return nil }
            return hundreds * 100 + rest
        }
        let digits: [Character: Int] = ["零": 0, "〇": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4,
                                        "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        var s = Substring(raw)
        while s.count > 1, let first = s.first, first == "零" || first == "〇" { s.removeFirst() }

        if let tenIndex = s.firstIndex(of: "十") {
            let before = s[..<tenIndex]
            let after = s[s.index(after: tenIndex)...]
            guard before.count <= 1, after.count <= 1 else { return nil }
            let tens = before.first.map { digits[$0] ?? -100 } ?? 1
            let ones = after.first.map { digits[$0] ?? -100 } ?? 0
            let value = tens * 10 + ones
            return value >= 0 ? value : nil
        }
        guard s.count == 1, let c = s.first else { return nil }
        return digits[c]
    }

    // MARK: - Note

    /// Longest phrases first so "的提醒" goes before "提醒"
    private static let fillerPattern =
        #"(帮我|请|麻烦)?(设置|添加|新建|加|建|设)(一个|个)?|的提醒|提醒一下|提醒我|提醒|叫我|记得"#

    private static func cleanNote(_ text: String) -> String {
        var note = text
        while remove(fillerPattern, from: &note) != nil {}
        let trim = CharacterSet.whitespacesAndNewlines
            .union(.punctuationCharacters)
            .union(CharacterSet(charactersIn: "，。、：；！？,.:;!?的"))
        return note.trimmingCharacters(in: trim)
    }

    // MARK: - Regex helpers

    private static func matches(_ pattern: String, in text: String) -> Bool {
        (try? NSRegularExpression(pattern: pattern))?
            .firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> (range: Range<String.Index>, groups: [String?])? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let range = Range(match.range, in: text) else { return nil }
        let groups = (1..<match.numberOfRanges).map { i in Range(match.range(at: i), in: text).map { String(text[$0]) } }
        return (range, groups)
    }

    /// Removes the first match and returns it
    @discardableResult
    private static func remove(_ pattern: String, from text: inout String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.range.length > 0,
              let range = Range(match.range, in: text) else { return nil }
        let found = String(text[range])
        text.removeSubrange(range)
        return found
    }
}
