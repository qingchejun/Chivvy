import Combine
import Foundation

enum AppLanguage: String, CaseIterable {
    case zh
    case en
}

/// The UI language, switchable at runtime from the main window or the menu bar
enum L10n {
    static let key = "appLanguage"

    static var current: AppLanguage {
        get {
            if let raw = UserDefaults.standard.string(forKey: key), let saved = AppLanguage(rawValue: raw) {
                return saved
            }
            // Decide once and keep it: the upgrade check below looks at keys the app writes
            // during normal use, so recomputing later would flip a new user to Chinese
            let language = defaultLanguage
            UserDefaults.standard.set(language.rawValue, forKey: key)
            return language
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    /// Chinese system → Chinese. Anyone upgrading from 2.0 (which was Chinese-only) keeps Chinese.
    static var defaultLanguage: AppLanguage {
        let defaults = UserDefaults.standard
        let upgraded = ["dailyReminders", "customPresets", "hasShownBackgroundTip"]
            .contains { defaults.object(forKey: $0) != nil }
        if upgraded { return .zh }
        return Locale.preferredLanguages.first?.hasPrefix("zh") == true ? .zh : .en
    }
}

/// Picks the string for the current UI language
func L(_ zh: String, _ en: String) -> String {
    L10n.current == .en ? en : zh
}

/// Publishes language changes so open windows can rebuild
@MainActor
final class LanguageStore: ObservableObject {
    static let shared = LanguageStore()

    @Published private(set) var language = L10n.current

    private init() {}

    func toggle() {
        set(language == .zh ? .en : .zh)
    }

    func set(_ newValue: AppLanguage) {
        guard newValue != language else { return }
        L10n.current = newValue
        language = newValue
    }
}

/// "1 小时 5 分钟" / "1 hr 5 min"; zero parts are left out
func durationLabel(_ seconds: Int) -> String {
    let h = seconds / 3600, m = seconds % 3600 / 60, s = seconds % 60
    var parts: [String] = []
    if h > 0 { parts.append(L("\(h) 小时", "\(h) hr")) }
    if m > 0 { parts.append(L("\(m) 分钟", "\(m) min")) }
    if s > 0 { parts.append(L("\(s) 秒", "\(s) sec")) }
    return parts.joined(separator: " ")
}
