import Foundation

// Minimal test harness: SwiftPM in Command Line Tools can't link manifests,
// so tests compile together with the logic files via Tests/run.sh.

var failures = 0
var passed = 0

func expect(_ condition: @autoclosure () -> Bool, _ message: String, line: Int = #line) {
    if condition() {
        passed += 1
    } else {
        failures += 1
        print("  ✗ line \(line): \(message)")
    }
}

func calendar(_ tz: String) -> Calendar {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: tz)!
    return cal
}

let shanghai = calendar("Asia/Shanghai")

/// Build a date in the given calendar: date(2026, 9, 30, 22, 0)
func date(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int, _ s: Int = 0, cal: Calendar = shanghai) -> Date {
    cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi, second: s))!
}

/// Runs `body` with the UI language set, then restores whatever was saved before
func with(_ language: AppLanguage, _ body: () -> Void) {
    let saved = UserDefaults.standard.string(forKey: L10n.key)
    L10n.current = language
    body()
    UserDefaults.standard.set(saved, forKey: L10n.key)
}

@main
enum TestRunner {
    static func main() {
        for (name, test) in scheduleTests + parserTests + hotKeyTests + localizationTests {
            let before = failures
            test()
            print(failures == before ? "✓ \(name)" : "✗ \(name)")
        }
        print("\n\(passed) assertions passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }
}
