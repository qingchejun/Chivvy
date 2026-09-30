import AppKit
import Combine

enum TimerState {
    case idle
    case running
    case paused
}

@MainActor
final class TimerManager: ObservableObject {
    static let shared = TimerManager()

    @Published var totalSeconds: Int = 0
    @Published var remainingSeconds: Int = 0
    @Published var timerState: TimerState = .idle
    @Published var note: String = ""
    @Published private(set) var lastMinutes: Int = 0
    @Published private(set) var lastSeconds: Int = 0
    @Published private(set) var lastNote: String = ""
    /// Increments each time a countdown finishes (not when cancelled)
    @Published private(set) var completionCount: Int = 0

    var hasLastTimer: Bool { lastMinutes > 0 || lastSeconds > 0 }

    private var endDate: Date?
    private var pausedRemaining: Int = 0
    private var timerCancellable: AnyCancellable?
    private let alertPanel = AlertPanel()

    var progress: Double {
        guard totalSeconds > 0 else { return 0 }
        return Double(remainingSeconds) / Double(totalSeconds)
    }

    var formattedTime: String {
        let m = remainingSeconds / 60
        let s = remainingSeconds % 60
        return String(format: "%02d:%02d", m, s)
    }

    private init() {
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.tick()
            }
        }
    }

    func start(minutes: Int, seconds: Int, note: String = "") {
        let total = minutes * 60 + seconds
        guard total > 0 else { return }

        lastMinutes = minutes
        lastSeconds = seconds
        lastNote = note
        self.note = note
        totalSeconds = total
        remainingSeconds = total
        endDate = Date().addingTimeInterval(Double(total))
        timerState = .running
        updateDockBadge()
        startTicking()
    }

    func repeatLast() {
        guard hasLastTimer else { return }
        start(minutes: lastMinutes, seconds: lastSeconds, note: lastNote)
    }

    func pause() {
        timerState = .paused
        pausedRemaining = remainingSeconds
        endDate = nil
        timerCancellable?.cancel()
        timerCancellable = nil
        updateDockBadge()
    }

    func resume() {
        endDate = Date().addingTimeInterval(Double(pausedRemaining))
        timerState = .running
        updateDockBadge()
        startTicking()
    }

    func cancel() {
        timerState = .idle
        timerCancellable?.cancel()
        timerCancellable = nil
        endDate = nil
        totalSeconds = 0
        remainingSeconds = 0
        note = ""
        updateDockBadge()
    }

    private func startTicking() {
        timerCancellable = Timer.publish(every: 0.25, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in
                    self.tick()
                }
            }
    }

    private func tick() {
        guard let endDate else { return }

        let remaining = Int(ceil(endDate.timeIntervalSinceNow))

        if remaining <= 0 {
            remainingSeconds = 0
            timerState = .idle
            timerCancellable?.cancel()
            timerCancellable = nil
            self.endDate = nil
            let finishedNote = note
            note = ""
            updateDockBadge()
            completionCount += 1
            NotificationManager.shared.sendTimerComplete(note: finishedNote)
            alertPanel.show(note: finishedNote)
        } else if remaining != remainingSeconds {
            remainingSeconds = remaining
            updateDockBadge()
        }
    }

    private func updateDockBadge() {
        switch timerState {
        case .running, .paused:
            NSApp.dockTile.badgeLabel = formattedTime
        case .idle:
            NSApp.dockTile.badgeLabel = nil
        }
    }
}
