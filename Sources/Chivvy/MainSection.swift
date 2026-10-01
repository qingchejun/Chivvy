import Foundation

/// The main window's sidebar sections; the last one shown is restored on launch
enum MainSection: String, CaseIterable {
    case timer
    case reminders
    case settings

    static let key = "mainSection"

    static func saved(in defaults: UserDefaults = .standard) -> MainSection {
        defaults.string(forKey: key).flatMap(MainSection.init(rawValue:)) ?? .timer
    }

    func save(in defaults: UserDefaults = .standard) {
        defaults.set(rawValue, forKey: Self.key)
    }

    var title: String {
        switch self {
        case .timer: return L("倒计时", "Countdown")
        case .reminders: return L("每日提醒", "Daily reminders")
        case .settings: return L("设置", "Settings")
        }
    }

    var symbol: String {
        switch self {
        case .timer: return "timer"
        case .reminders: return "bell"
        case .settings: return "slider.horizontal.3"
        }
    }
}
