import AppKit
import Combine
import SwiftUI

/// Global shortcut → speak one sentence →
/// - "一分钟后提醒我睡觉": starts a countdown right away
/// - "每天晚上十一点提醒我睡觉": confirm card, then saved as a daily reminder
@MainActor
final class VoiceReminderController: ObservableObject {
    static let shared = VoiceReminderController()

    enum Phase {
        case listening(transcript: String)
        case confirm(draft: DailyReminder, heard: String, warning: String?)
        case saved(reminder: DailyReminder, heard: String)
        case countdownStarted(seconds: Int, note: String)
        /// A countdown is already running; ask before replacing it
        case replaceCountdown(seconds: Int, note: String, heard: String)
        case failed(message: String, heard: String?)
    }

    @Published private(set) var phase: Phase = .listening(transcript: "")
    @Published private(set) var hotKeyCombo: HotKeyCombo
    private static let hotKeyDefaultsKey = "voiceReminderHotKey"

    private let store = ReminderStore.shared
    private let capture = SpeechCapture()
    private var hotKey: GlobalHotKey?
    private var panel: NSPanel?
    private var autoHide: DispatchWorkItem?
    /// Bumped by close(): a permission prompt answered after the user cancelled must not start the mic
    private var listenRequest = 0
    private var awaitingPermission = false
    /// Where the panel's top-left sits; re-applied when the content grows (confirm card is taller)
    private var panelTopLeft: NSPoint?
    /// The app the user was in, re-activated when the panel closes
    private var previousApp: NSRunningApplication?
    private var cancellables = Set<AnyCancellable>()

    private init() {
        if let data = UserDefaults.standard.data(forKey: Self.hotKeyDefaultsKey),
           let saved = try? JSONDecoder().decode(HotKeyCombo.self, from: data) {
            hotKeyCombo = saved
        } else {
            hotKeyCombo = .defaultVoiceReminder
        }

        capture.onPartial = { [weak self] text in
            self?.phase = .listening(transcript: text)
        }
        capture.onFinish = { [weak self] text in
            self?.handle(text)
        }
        capture.onError = { [weak self] message in
            self?.phase = .failed(message: message, heard: nil)
        }

        $phase
            .sink { [weak self] _ in
                // After SwiftUI resizes the panel for the new content, pin it back to the top
                DispatchQueue.main.async { self?.anchorPanel() }
            }
            .store(in: &cancellables)
    }

    func start() {
        registerHotKey(hotKeyCombo)
    }

    @discardableResult
    private func registerHotKey(_ combo: HotKeyCombo) -> Bool {
        hotKey = nil  // unregister the old one first, or re-registering the same combo fails
        hotKey = GlobalHotKey(combo) { [weak self] in
            Task { @MainActor in self?.toggleListening() }
        }
        return hotKey != nil
    }

    /// While the shortcut recorder listens, the current hotkey must not fire
    func suspendHotKey() {
        hotKey = nil
    }

    func resumeHotKey() {
        registerHotKey(hotKeyCombo)
    }

    /// Returns false (and keeps the old shortcut) if another app already owns the combo
    func setHotKey(_ combo: HotKeyCombo) -> Bool {
        guard registerHotKey(combo) else {
            registerHotKey(hotKeyCombo)
            return false
        }
        hotKeyCombo = combo
        UserDefaults.standard.set(try? JSONEncoder().encode(combo), forKey: Self.hotKeyDefaultsKey)
        return true
    }

    // MARK: - Entry points

    func toggleListening() {
        if capture.isRunning {
            capture.stop()
        } else {
            beginListening()
        }
    }

    func beginListening() {
        // Already starting (permission prompt up) or recording: pressing again must not start a second tap
        guard !awaitingPermission, !capture.isRunning else { return }

        phase = .listening(transcript: "")
        showPanel()
        listenRequest += 1
        let request = listenRequest
        awaitingPermission = true
        SpeechCapture.requestPermissions { [weak self] error in
            guard let self, request == self.listenRequest else { return }
            self.awaitingPermission = false
            if let error {
                self.phase = .failed(message: error, heard: nil)
            } else {
                self.capture.start()
            }
        }
    }

    // MARK: - Parse & save

    private func handle(_ text: String) {
        let heard = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !heard.isEmpty else {
            phase = .failed(message: L("没听清，再试一次吧。", "Didn't catch that. Try again?"), heard: nil)
            return
        }

        switch ReminderParser.parseCommand(heard) {
        case .countdown(let seconds, let note):
            if TimerManager.shared.timerState == .idle {
                startCountdown(seconds: seconds, note: note)
            } else {
                phase = .replaceCountdown(seconds: seconds, note: note, heard: heard)
            }
        case .daily(let parsed):
            confirmDaily(parsed, heard: heard)
        }
    }

    func startCountdown(seconds: Int, note: String) {
        TimerManager.shared.start(minutes: seconds / 60, seconds: seconds % 60, note: note)
        phase = .countdownStarted(seconds: seconds, note: note)
        scheduleAutoHide(after: 4)
    }

    func undoCountdown() {
        TimerManager.shared.cancel()
        close()
    }

    private func confirmDaily(_ parsed: ParsedReminder, heard: String) {
        var draft = DailyReminder(
            hour: parsed.hour ?? 23,
            minute: parsed.minute ?? 0,
            note: parsed.note,
            weekdays: parsed.weekdays
        )
        draft.isEnabled = true

        var warning: String?
        if parsed.isOneOff {
            warning = L("Chivvy 暂时只支持每天重复的提醒，保存后会按下面的规则重复。", "Chivvy only supports repeating reminders for now; this one will repeat as set below.")
        } else if parsed.hour == nil {
            warning = L("没听出时间，请选一下。", "No time heard. Please pick one.")
        }

        phase = .confirm(draft: draft, heard: heard, warning: warning)
    }

    func save(_ reminder: DailyReminder, heard: String) {
        guard store.reminders.count < DailyReminder.maxCount else {
            phase = .failed(message: L("最多只能有 \(DailyReminder.maxCount) 条提醒，先在提醒窗口里删掉一些吧。",
                                               "You can have up to \(DailyReminder.maxCount) reminders. Delete some in the Reminders window first."), heard: heard)
            return
        }
        store.reminders.append(reminder)
        phase = .saved(reminder: reminder, heard: heard)
        scheduleAutoHide(after: 5)
    }

    func undo(_ reminder: DailyReminder) {
        store.reminders.removeAll { $0.id == reminder.id }
        close()
    }

    func close() {
        listenRequest += 1
        awaitingPermission = false
        capture.cancel()
        autoHide?.cancel()
        guard let panel, panel.isVisible else { return }
        panel.orderOut(nil)
        // Hand focus back to what the user was doing
        if let previousApp, previousApp != NSRunningApplication.current {
            previousApp.activate(options: [])
        }
        previousApp = nil
    }

    // MARK: - Panel

    private func showPanel() {
        autoHide?.cancel()
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if !panel.isVisible {
            previousApp = NSWorkspace.shared.frontmostApplication
            if let screen = NSScreen.main {
                // Top-center, like Spotlight
                let frame = screen.visibleFrame
                panelTopLeft = NSPoint(x: frame.midX - panel.frame.width / 2, y: frame.maxY - 120)
            }
        }
        anchorPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
    }

    private func anchorPanel() {
        guard let panel, let panelTopLeft else { return }
        panel.setFrameTopLeftPoint(panelTopLeft)
    }

    private func makePanel() -> NSPanel {
        let panel = KeyablePanel(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 200),
            styleMask: [.borderless, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false

        let hosting = NSHostingView(rootView: LanguageRoot { VoiceReminderView(controller: self) })
        panel.contentView = hosting
        return panel
    }

    private func scheduleAutoHide(after seconds: TimeInterval) {
        autoHide?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.close() }
        autoHide = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }
}

/// Borderless panels can't become key by default; the confirm card needs typing
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

// MARK: - View

private struct VoiceReminderView: View {
    @ObservedObject var controller: VoiceReminderController

    var body: some View {
        Group {
            switch controller.phase {
            case .listening(let transcript):
                listening(transcript)
            case .confirm(let draft, let heard, let warning):
                ConfirmCard(initial: draft, heard: heard, warning: warning, controller: controller)
                    // New draft (e.g. a second recording) resets the card's local state
                    .id(draft.id)
            case .saved(let reminder, let heard):
                saved(reminder, heard: heard)
            case .countdownStarted(let seconds, let note):
                countdownStarted(seconds, note: note)
            case .replaceCountdown(let seconds, let note, let heard):
                replaceCountdown(seconds, note: note, heard: heard)
            case .failed(let message, let heard):
                failed(message, heard: heard)
            }
        }
        .padding(20)
        .frame(width: 420, alignment: .leading)
        .panelCard()
        .tint(Theme.brand)
    }

    private func listening(_ transcript: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VoiceHeader(badge: StatusBadge(symbol: "mic.fill", tone: .brand), title: L("正在听…", "Listening…")) {
                Button(L("取消", "Cancel")) { controller.close() }
                    .buttonStyle(.chivvy(.secondary, size: .small))
                    .keyboardShortcut(.cancelAction)
            }
            Text(transcript.isEmpty ? L("比如：每天晚上十一点提醒我睡觉 / 十分钟后提醒我关火",
                                                   "Speak Mandarin, e.g. 每天晚上十一点提醒我睡觉 / 十分钟后提醒我关火") : transcript)
                .font(.system(size: 17, weight: transcript.isEmpty ? .regular : .medium))
                .foregroundStyle(transcript.isEmpty ? .tertiary : .primary)
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .topLeading)
            Text(L("说完停顿 2 秒自动结束，或再按 \(controller.hotKeyCombo.label) 结束",
                    "Stops after a 2-second pause, or press \(controller.hotKeyCombo.label) again"))
                .font(Theme.Font.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func saved(_ reminder: DailyReminder, heard: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VoiceHeader(badge: StatusBadge(symbol: "checkmark", tone: .success), title: L("已添加提醒", "Reminder added"))
            Text("\(reminder.timeLabel) · \(reminder.daysSummary()) · \(reminder.note.isEmpty ? L("无备注", "No note") : reminder.note)")
                .font(.system(size: 17, weight: .medium).monospacedDigit())
            heardLine(heard)
            VoiceButtons {
                Button(L("撤销", "Undo")) { controller.undo(reminder) }
                    .buttonStyle(.chivvy(.secondary))
                Button(L("好", "OK")) { controller.close() }
                    .buttonStyle(.chivvy(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func countdownStarted(_ seconds: Int, note: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VoiceHeader(badge: StatusBadge(symbol: "timer", tone: .success),
                        title: L("已开始倒计时 ", "Countdown started: ") + durationLabel(seconds))
            if !note.isEmpty {
                Text(L("到时提醒：", "Reminder: ") + note)
                    .font(.system(size: 15, weight: .medium))
            }
            VoiceButtons {
                Button(L("撤销", "Undo")) { controller.undoCountdown() }
                    .buttonStyle(.chivvy(.secondary))
                Button(L("好", "OK")) { controller.close() }
                    .buttonStyle(.chivvy(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func replaceCountdown(_ seconds: Int, note: String, heard: String) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VoiceHeader(badge: StatusBadge(symbol: "timer", tone: .brandSoft),
                        title: L("已有一个倒计时在进行，要替换吗？", "A countdown is already running. Replace it?"))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(L("当前：", "Current: ") + "\(TimerManager.shared.formattedTime)\(TimerManager.shared.note.isEmpty ? "" : " · \(TimerManager.shared.note)")")
                    .foregroundStyle(.secondary)
                Text(L("新的：", "New: ") + "\(durationLabel(seconds))\(note.isEmpty ? "" : " · \(note)")")
            }
            .font(Theme.Font.body.monospacedDigit())
            VoiceButtons {
                Button(L("取消", "Cancel")) { controller.close() }
                    .buttonStyle(.chivvy(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(L("替换", "Replace")) { controller.startCountdown(seconds: seconds, note: note) }
                    .buttonStyle(.chivvy(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func failed(_ message: String, heard: String?) -> some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VoiceHeader(badge: StatusBadge(symbol: "mic.slash", tone: .neutral), title: message)
            if let heard {
                heardLine(heard)
            }
            VoiceButtons {
                Button(L("关闭", "Close")) { controller.close() }
                    .buttonStyle(.chivvy(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(L("再说一次", "Try Again")) { controller.beginListening() }
                    .buttonStyle(.chivvy(.primary))
                    .keyboardShortcut(.defaultAction)
            }
        }
    }

    private func heardLine(_ heard: String) -> some View {
        Text(L("听到的是：", "Heard: ") + heard)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
    }
}

/// Badge + title row at the top of each voice state
private struct VoiceHeader<Trailing: View>: View {
    let badge: StatusBadge
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 10) {
            badge
            Text(title)
                .font(Theme.Font.headline)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Theme.Space.s)
            trailing()
        }
    }
}

extension VoiceHeader where Trailing == EmptyView {
    init(badge: StatusBadge, title: String) {
        self.init(badge: badge, title: title) { EmptyView() }
    }
}

/// Right-aligned button row
private struct VoiceButtons<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Spacer()
            content()
        }
        .padding(.top, Theme.Space.xs)
    }
}

private struct ConfirmCard: View {
    let heard: String
    let warning: String?
    let controller: VoiceReminderController
    @State private var draft: DailyReminder

    init(initial: DailyReminder, heard: String, warning: String?, controller: VoiceReminderController) {
        self.heard = heard
        self.warning = warning
        self.controller = controller
        _draft = State(initialValue: initial)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            VoiceHeader(badge: StatusBadge(symbol: "bell.fill", tone: .brandSoft), title: L("添加这条提醒？", "Add this reminder?"))
            VStack(alignment: .leading, spacing: Theme.Space.xs) {
                Text(L("听到的是：", "Heard: ") + heard)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                if let warning {
                    Text(warning)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.brandText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ReminderForm(draft: $draft)

            HStack(spacing: Theme.Space.s) {
                Button(L("重新说", "Say It Again")) { controller.beginListening() }
                    .buttonStyle(.chivvy(.text))
                Spacer()
                Button(L("取消", "Cancel")) { controller.close() }
                    .buttonStyle(.chivvy(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(L("保存", "Save")) { controller.save(draft, heard: heard) }
                    .buttonStyle(.chivvy(.primary))
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft.weekdays.isEmpty)
            }
            .padding(.top, Theme.Space.xs)
        }
    }
}
