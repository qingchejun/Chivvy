import AppKit
import Combine
@preconcurrency import UserNotifications

@MainActor
final class ReminderStore: ObservableObject {
    static let shared = ReminderStore()

    @Published var reminders: [DailyReminder] {
        didSet { save() }
    }

    private let key = "dailyReminders"

    private init() {
        if let data = UserDefaults.standard.data(forKey: key),
           let saved = try? JSONDecoder().decode([DailyReminder].self, from: data) {
            reminders = saved
        } else {
            reminders = []
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(reminders) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }
}

/// Fires daily reminders two ways:
/// - In-app: full alert panel + looping sound while Chivvy is running.
/// - System: repeating calendar notifications, delivered by macOS even if Chivvy has quit.
@MainActor
final class ReminderScheduler: ObservableObject {
    static let shared = ReminderScheduler()

    nonisolated static let notificationPrefix = "daily-"
    private nonisolated static let snoozePrefix = "\(notificationPrefix)snooze-"
    /// A reminder missed while asleep (or before launch) is still shown within this window
    private let missedGrace: TimeInterval = 30 * 60
    private static let snoozeKey = "pendingSnoozes"

    /// Minutes offered as "N 分钟后". Override for quick testing:
    /// defaults write com.qingche.Tick snoozeOptionsMinutes -array -int 1 -int 2
    private var snoozeOptions: [Int] {
        let custom = (UserDefaults.standard.array(forKey: "snoozeOptionsMinutes") as? [Int])?.filter { $0 > 0 }
        return custom?.isEmpty == false ? custom! : [5, 10]
    }

    @Published private(set) var upcoming: ScheduledReminder?

    private let store = ReminderStore.shared
    /// One panel per reminder, so a second reminder doesn't wipe out the first one's snooze buttons
    private var alertPanels: [UUID: AlertPanel] = [:]
    private static let lastCheckKey = "reminderLastCheck"
    /// Persisted so a relaunch doesn't re-show alerts that already fired
    private var lastCheck = Date() {
        didSet { UserDefaults.standard.set(lastCheck, forKey: Self.lastCheckKey) }
    }
    private var fireTimer: Timer?
    /// Pending snoozes, one per reminder
    private var snoozes: [UUID: SnoozeState] = [:] {
        didSet {
            let data = try? JSONEncoder().encode(Array(snoozes.values))
            UserDefaults.standard.set(data, forKey: Self.snoozeKey)
        }
    }
    private var snoozeTimers: [UUID: Timer] = [:]
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    func start() {
        // Read before subscribing: the subscription's first emission overwrites lastCheck
        let savedCheck = UserDefaults.standard.object(forKey: Self.lastCheckKey) as? Date
        removeOrphanedSystemNotifications()

        store.$reminders
            .sink { [weak self] newValue in
                guard let self else { return }
                // $reminders emits in willSet: store.reminders still holds the old list here
                self.syncSystemNotifications(old: self.store.reminders, new: newValue)
                // Edits only look forward; a just-added 22:30 reminder at 22:40 isn't "missed"
                self.lastCheck = Date()
                for id in self.snoozes.keys where !newValue.contains(where: { $0.id == id && $0.isEnabled }) {
                    self.cancelSnooze(id)
                }
                self.reschedule(newValue)
            }
            .store(in: &cancellables)

        // Timers don't count time asleep and the wall clock can jump; re-evaluate on these events
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                self?.reevaluateSnoozes()
                self?.check()
            }
        }
        for name in [Notification.Name.NSSystemClockDidChange, .NSSystemTimeZoneDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in
                    NSTimeZone.resetSystemTimeZone()
                    self?.reevaluateSnoozes()
                    // After a clock jump, only look forward from now
                    self?.lastCheck = Date()
                    self?.check()
                }
            }
        }

        // Restore snoozes first, so check() knows those occurrences were already handled
        if let data = UserDefaults.standard.data(forKey: Self.snoozeKey),
           let saved = try? JSONDecoder().decode([SnoozeState].self, from: data) {
            snoozes = Dictionary(saved.map { ($0.reminderID, $0) }, uniquingKeysWith: { _, latest in latest })
        }
        reevaluateSnoozes()

        // Launched at login a few minutes past bedtime → still show it; relaunched right after it fired → don't
        lastCheck = ReminderSchedule.launchCheckpoint(
            saved: savedCheck,
            now: Date(),
            grace: missedGrace
        )
        check()
    }

    // MARK: - In-app firing

    private func check() {
        let now = Date()
        let due = ReminderSchedule.due(in: store.reminders, from: lastCheck, to: now, grace: missedGrace)
            // An occurrence the user already snoozed isn't new (e.g. relaunch during a snooze)
            .filter { snoozes[$0.reminder.id] == nil }
        lastCheck = now
        for occurrence in due {
            fire(occurrence.reminder)
        }
        reschedule(store.reminders)
    }

    private func reschedule(_ reminders: [DailyReminder]) {
        fireTimer?.invalidate()
        fireTimer = nil

        upcoming = ReminderSchedule.next(in: reminders, after: Date())
        guard let upcoming else { return }

        let timer = Timer(fire: upcoming.date, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.check() }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        fireTimer = timer
    }

    /// - Parameter snoozeCount: snoozes already used for this occurrence (0 = on time)
    private func fire(_ reminder: DailyReminder, snoozeCount: Int = 0) {
        let state = SnoozeState(reminderID: reminder.id, fireDate: Date(), count: snoozeCount)
        let options = state.canSnoozeAgain ? snoozeOptions : []
        let panel = alertPanels[reminder.id] ?? AlertPanel()
        alertPanels[reminder.id] = panel
        panel.show(
            AlertText.reminder(reminder, snoozeCount: snoozeCount),
            snoozeActions: options.map { minutes in
                AlertAction(label: L("\(minutes) 分钟后", "In \(minutes) min")) { [weak self] in
                    self?.scheduleSnooze(reminder.id, minutes: minutes, count: snoozeCount + 1)
                }
            }
        )
        clearDeliveredNotifications(for: reminder)
    }

    private static func dueTitle(_ reminder: DailyReminder) -> String {
        L("\(reminder.timeLabel) 到了", "It's \(reminder.timeLabel)")
    }

    private static func snoozedTitle(_ reminder: DailyReminder) -> String {
        L("稍后提醒 · \(reminder.timeLabel)", "Snoozed · \(reminder.timeLabel)")
    }

    private static func body(for reminder: DailyReminder) -> String {
        reminder.note.isEmpty ? L("每日提醒", "Daily reminder") : reminder.note
    }

    // MARK: - Snooze

    private func scheduleSnooze(_ id: UUID, minutes: Int, count: Int) {
        // Re-read: the reminder may have been edited, turned off or deleted while the panel was open
        guard let reminder = store.reminders.first(where: { $0.id == id && $0.isEnabled }) else { return }
        cancelSnooze(id)
        let state = SnoozeState(reminderID: id,
                                fireDate: Date().addingTimeInterval(TimeInterval(minutes * 60)),
                                count: count)
        snoozes[id] = state
        armSnoozeTimer(state)

        // Backup in case Chivvy quits before the snooze is due
        addSnoozeBackup(for: reminder, after: TimeInterval(minutes * 60))
    }

    /// Adding with the same identifier replaces an existing backup
    private func addSnoozeBackup(for reminder: DailyReminder, after interval: TimeInterval) {
        let content = UNMutableNotificationContent()
        content.title = Self.snoozedTitle(reminder)
        content.body = Self.body(for: reminder)
        content.sound = .default
        let request = UNNotificationRequest(
            identifier: Self.snoozePrefix + reminder.id.uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
        )
        UNUserNotificationCenter.current().add(request)
    }

    private func armSnoozeTimer(_ state: SnoozeState) {
        snoozeTimers[state.reminderID]?.invalidate()
        let timer = Timer(fire: state.fireDate, interval: 0, repeats: false) { [weak self] _ in
            Task { @MainActor in self?.fireSnooze(state) }
        }
        timer.tolerance = 1
        RunLoop.main.add(timer, forMode: .common)
        snoozeTimers[state.reminderID] = timer
    }

    private func fireSnooze(_ state: SnoozeState) {
        snoozeTimers[state.reminderID] = nil
        snoozes[state.reminderID] = nil
        // Use the current version; skip if it was deleted or turned off meanwhile
        guard let current = store.reminders.first(where: { $0.id == state.reminderID }),
              current.isEnabled else { return }
        fire(current, snoozeCount: state.count)
    }

    /// Re-arms, fires or drops each snooze against the current wall clock.
    /// Needed at launch and after sleep: a Timer's countdown pauses while the Mac sleeps,
    /// so a 23:10 snooze after an overnight sleep would otherwise pop up the next morning.
    private func reevaluateSnoozes() {
        for state in snoozes.values {
            switch state.restoreAction(now: Date(), grace: missedGrace) {
            case .schedule:
                armSnoozeTimer(state)
            case .fireNow:
                fireSnooze(state)
            case .discard:
                cancelSnooze(state.reminderID)
            }
        }
    }

    private func cancelSnooze(_ id: UUID) {
        snoozeTimers[id]?.invalidate()
        snoozeTimers[id] = nil
        snoozes[id] = nil
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [Self.snoozePrefix + id.uuidString])
    }

    // MARK: - System notifications (backup when Chivvy isn't running)

    /// Suffix 0 = every-day request, 1…7 = per-weekday requests
    private nonisolated static func identifiers(for reminder: DailyReminder) -> [String] {
        (0...7).map { "\(notificationPrefix)\(reminder.id.uuidString)-\($0)" }
    }

    /// Removes by deterministic IDs instead of a pending-requests snapshot, so back-to-back
    /// saves are applied in call order and can't leave a deleted reminder scheduled.
    private func syncSystemNotifications(old: [DailyReminder], new: [DailyReminder]) {
        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: (old + new).flatMap(Self.identifiers(for:)))

        for reminder in new where reminder.isEnabled {
            let content = UNMutableNotificationContent()
            content.title = Self.dueTitle(reminder)
            content.body = Self.body(for: reminder)
            content.sound = .default

            // One request for every day, otherwise one per weekday (pending requests are capped at 64)
            let weekdays: [Int?] = reminder.weekdays == DailyReminder.everyDay ? [nil] : reminder.weekdays.map { $0 }
            for weekday in weekdays {
                let trigger = UNCalendarNotificationTrigger(
                    dateMatching: DateComponents(hour: reminder.hour, minute: reminder.minute, weekday: weekday),
                    repeats: true
                )
                let request = UNNotificationRequest(
                    identifier: "\(Self.notificationPrefix)\(reminder.id.uuidString)-\(weekday ?? 0)",
                    content: content,
                    trigger: trigger
                )
                center.add(request) { error in
                    if let error {
                        print("Reminder notification error: \(error)")
                    }
                }
            }
        }
    }

    /// Re-adds pending system notifications so their text matches the new UI language
    func languageDidChange() {
        syncSystemNotifications(old: store.reminders, new: store.reminders)
        for state in snoozes.values {
            guard let reminder = store.reminders.first(where: { $0.id == state.reminderID && $0.isEnabled }) else { continue }
            let remaining = state.fireDate.timeIntervalSinceNow
            guard remaining > 1 else { continue }
            addSnoozeBackup(for: reminder, after: remaining)
        }
    }

    /// Clears requests left behind by reminders that no longer exist (e.g. from older builds).
    /// Runs once at launch, before any sync, so it can't race with one.
    private func removeOrphanedSystemNotifications() {
        let known = Set(store.reminders.flatMap(Self.identifiers(for:)))
        let center = UNUserNotificationCenter.current()
        center.getPendingNotificationRequests { pending in
            let orphans = pending.map(\.identifier)
                // Snooze backups are one-shot and cleaned up by cancelSnooze; leave them alone
                .filter { $0.hasPrefix(Self.notificationPrefix) && !$0.hasPrefix(Self.snoozePrefix) && !known.contains($0) }
            center.removePendingNotificationRequests(withIdentifiers: orphans)
        }
    }

    /// The in-app panel already covers this reminder; drop the duplicate system banner.
    /// The banner can land a moment after our timer, so clear again shortly after.
    private func clearDeliveredNotifications(for reminder: DailyReminder) {
        let ids = Self.identifiers(for: reminder) + [Self.snoozePrefix + reminder.id.uuidString]
        let center = UNUserNotificationCenter.current()
        center.removeDeliveredNotifications(withIdentifiers: ids)
        for delay in [5.0, 30.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                center.removeDeliveredNotifications(withIdentifiers: ids)
            }
        }
    }
}
