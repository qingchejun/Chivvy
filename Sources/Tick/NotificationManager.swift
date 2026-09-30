import AppKit
import UserNotifications

final class NotificationManager: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationManager()
    private var soundTimer: Timer?
    private var autoStopTimer: Timer?
    /// Alerts currently wanting the sound; it keeps looping until all are dismissed
    private var soundOwners = Set<ObjectIdentifier>()

    private override init() {
        super.init()
        UNUserNotificationCenter.current().delegate = self
    }

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, error in
            if let error {
                print("Notification permission error: \(error)")
            }
        }
    }

    /// Loop alert sound until every owner stops it (auto-stop 45s after the latest start)
    func startAlertSound(for owner: AnyObject) {
        soundOwners.insert(ObjectIdentifier(owner))

        autoStopTimer?.invalidate()
        autoStopTimer = Timer.scheduledTimer(withTimeInterval: 45, repeats: false) { [weak self] _ in
            self?.stopAllSounds()
        }

        // Already looping for another alert; don't start a second loop
        guard soundTimer == nil else { return }
        NSSound(named: .init("Glass"))?.play()
        soundTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { _ in
            NSSound(named: .init("Glass"))?.play()
        }
    }

    func stopAlertSound(for owner: AnyObject) {
        soundOwners.remove(ObjectIdentifier(owner))
        if soundOwners.isEmpty {
            stopAllSounds()
        }
    }

    func sendTimerComplete(note: String = "") {
        // System notification as backup
        let content = UNMutableNotificationContent()
        content.title = "时间到！"
        content.body = note.isEmpty ? "倒计时已结束。" : note
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: UUID().uuidString,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 0.1, repeats: false)
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("Notification error: \(error)")
            }
        }
    }

    private func stopAllSounds() {
        soundOwners.removeAll()
        soundTimer?.invalidate()
        soundTimer = nil
        autoStopTimer?.invalidate()
        autoStopTimer = nil
        NSSound(named: .init("Glass"))?.stop()
    }

    // Show notification even when app is in foreground
    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // While Tick runs, daily reminders are shown by the in-app alert panel instead
        if notification.request.identifier.hasPrefix(ReminderScheduler.notificationPrefix) {
            completionHandler([])
            return
        }
        completionHandler([.banner, .sound])
    }
}
