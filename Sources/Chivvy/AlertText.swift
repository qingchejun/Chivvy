import Foundation

/// What the full-screen alert says. Kept apart from the view so the wording is testable.
struct AlertText: Equatable {
    struct Snooze: Equatable {
        let used: Int
        let exhausted: Bool
        let text: String
    }

    /// Small line above the headline: when, and what kind of alert
    let eyebrow: String
    /// The thing to do, in large type
    let title: String
    /// Snooze progress; nil before the first snooze
    let snooze: Snooze?

    static func reminder(_ reminder: DailyReminder, snoozeCount: Int) -> AlertText {
        let kind = reminder.isOneOff ? L("提醒", "Reminder") : L("每日提醒", "Daily reminder")
        let hasNote = !reminder.note.isEmpty
        return AlertText(
            eyebrow: hasNote ? "\(reminder.timeLabel) · \(kind)" : kind,
            title: hasNote ? reminder.note : L("\(reminder.timeLabel) 到了", "It's \(reminder.timeLabel)"),
            snooze: snoozeCount > 0 ? snooze(used: snoozeCount) : nil
        )
    }

    static func timer(note: String, seconds: Int) -> AlertText {
        AlertText(
            eyebrow: L("\(durationLabel(seconds))倒计时结束", "\(durationLabel(seconds)) countdown done"),
            title: note.isEmpty ? L("时间到", "Time's up") : note,
            snooze: nil
        )
    }

    private static func snooze(used: Int) -> Snooze {
        let left = max(SnoozeState.maxCount - used, 0)
        let text: String
        if left == 0 {
            text = L("已推迟 \(used) 次，不能再推迟了", "Snoozed \(used) times · no more snoozes")
        } else {
            text = L("已推迟 \(used) 次，还能推迟 \(left) 次",
                     used == 1 ? "Snoozed once · \(left) left" : "Snoozed \(used) times · \(left) left")
        }
        return Snooze(used: used, exhausted: left == 0, text: text)
    }
}
