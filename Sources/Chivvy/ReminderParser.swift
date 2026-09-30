import Foundation

/// What a spoken / typed sentence like "每天晚上十一点提醒我睡觉" means as a reminder
struct ParsedReminder: Equatable {
    var hour: Int?
    var minute: Int?
    var weekdays: Set<Int>
    var note: String
    /// Mentions a specific day ("明天", "10月3号"…); Chivvy only supports repeating reminders
    var isOneOff: Bool
}

/// What a voice sentence asks for
enum VoiceCommand: Equatable {
    /// "一分钟后提醒我睡觉", "倒计时25分钟"
    case countdown(seconds: Int, note: String)
    /// "每天晚上十一点提醒我睡觉"
    case daily(ParsedReminder)
}

/// Rule-based parser for short Chinese reminder sentences.
/// Order matters: repeat rules are cut out first, then the time, and what's left is the note.
enum ReminderParser {
    /// Relative durations ("X分钟后") mean a countdown; everything else is a daily reminder
    static func parseCommand(_ input: String) -> VoiceCommand {
        var text = normalize(input)
        if let seconds = extractCountdown(&text) {
            return .countdown(seconds: seconds, note: cleanNote(text))
        }
        return .daily(parse(input))
    }

    static func parse(_ input: String) -> ParsedReminder {
        var text = normalize(input)
        let isOneOff = !text.contains("每") && !text.contains("天天") && matches(oneOffPattern, in: text)

        let weekdays = extractWeekdays(&text)
        let time = extractTime(&text) ?? extractTimeWithDetector(&text)

        return ParsedReminder(
            hour: time?.hour,
            minute: time?.minute,
            weekdays: weekdays,
            note: cleanNote(text),
            isOneOff: isOneOff
        )
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

    // MARK: - Repeat rules

    private static let oneOffPattern =
        #"明天|明早|明晚|后天|今天|今晚|今早|\d{1,2}月\d{1,2}[日号]|下周|下个?星期|下个?礼拜"#

    private static let weekdayRangePattern =
        #"(每个?)?工作日|(每)?(周|星期|礼拜)一(到|至|-|~)(周|星期|礼拜)?五"#
    private static let weekendPattern = #"(每个?)?周末"#
    /// "每周一三五", "周二和周四", "星期六、星期天"
    private static let weekdayListPattern =
        #"(每个?)?(周|星期|礼拜)[一二三四五六日天](([、,，和及与]|和|及)?(周|星期|礼拜)?[一二三四五六日天])*"#
    private static let everyDayPattern = #"每天|每日|天天"#

    private static func extractWeekdays(_ text: inout String) -> Set<Int> {
        if remove(weekdayRangePattern, from: &text) != nil {
            return DailyReminder.weekdaysOnly
        }
        if remove(weekendPattern, from: &text) != nil {
            return DailyReminder.weekendsOnly
        }
        if let phrase = remove(weekdayListPattern, from: &text) {
            // Drop the prefixes so "星期" / "礼拜" / "周" don't contribute characters
            let digits = phrase
                .replacingOccurrences(of: "星期", with: "")
                .replacingOccurrences(of: "礼拜", with: "")
                .replacingOccurrences(of: "周", with: "")
            let map: [Character: Int] = ["日": 1, "天": 1, "一": 2, "二": 3, "三": 4, "四": 5, "五": 6, "六": 7]
            let days = Set(digits.compactMap { map[$0] })
            if !days.isEmpty { return days }
        }
        _ = remove(everyDayPattern, from: &text)
        return DailyReminder.everyDay
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
        + "(?::([0-9]{2})|[点时](?:(半)|(一刻)|(三刻)|(\(number))分?)?)"

    private static func extractTime(_ text: inout String) -> (hour: Int, minute: Int)? {
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

        let hour = adjust(hour: rawHour, period: group(1))
        guard (0..<24).contains(hour), (0..<60).contains(minute) else { return nil }

        if let range = Range(match.range, in: text) {
            text.removeSubrange(range)
        }
        return (hour, minute)
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
    private static func extractTimeWithDetector(_ text: inout String) -> (hour: Int, minute: Int)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue),
              let match = detector.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let date = match.date,
              let range = Range(match.range, in: text),
              // "明天" alone is a date without a time; the detector would make it 12:00
              text[range].range(of: "点|时|:|分|am|pm", options: [.regularExpression, .caseInsensitive]) != nil
        else { return nil }
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        text.removeSubrange(range)
        return (parts.hour ?? 0, parts.minute ?? 0)
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
