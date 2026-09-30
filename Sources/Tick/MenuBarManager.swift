import AppKit
import SwiftUI
import Combine

@MainActor
final class MenuBarManager: NSObject {
    private(set) var statusItem: NSStatusItem?

    var statusButton: NSStatusBarButton? {
        statusItem?.button
    }
    private let timerManager: TimerManager
    private var cancellables = Set<AnyCancellable>()
    private var blinkTimer: Timer?
    private var blinkVisible = true
    private var popover: NSPopover?

    init(timerManager: TimerManager) {
        self.timerManager = timerManager
        super.init()
        setupStatusItem()
        observeTimer()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Tick")
            button.target = self
            button.action = #selector(statusBarClicked)
        }
    }

    @objc private func statusBarClicked() {
        if let popover, popover.isShown {
            popover.performClose(nil)
            return
        }

        let pop = NSPopover()
        pop.behavior = .transient
        pop.contentSize = NSSize(width: 220, height: 0)
        pop.contentViewController = NSHostingController(
            rootView: MenuBarPopoverView(timerManager: timerManager, presetStore: PresetStore.shared) {
                pop.performClose(nil)
            }
        )

        if let button = statusItem?.button {
            pop.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        }
        popover = pop
    }

    private func observeTimer() {
        timerManager.$remainingSeconds
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
            }
            .store(in: &cancellables)

        timerManager.$timerState
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.updateDisplay()
                self?.updateBlink()
            }
            .store(in: &cancellables)
    }

    private func updateDisplay() {
        guard let button = statusItem?.button else { return }

        switch timerManager.timerState {
        case .idle:
            button.title = ""
            button.image = NSImage(systemSymbolName: "timer", accessibilityDescription: "Tick")
            button.contentTintColor = nil

        case .running:
            button.image = nil
            button.title = timerManager.formattedTime
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
            button.contentTintColor = nil

        case .paused:
            button.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: L("已暂停", "Paused"))
            button.title = " \(timerManager.formattedTime)"
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 0, weight: .regular)
        }
    }

    private func updateBlink() {
        blinkTimer?.invalidate()
        blinkTimer = nil
        blinkVisible = true

        if timerManager.timerState == .paused {
            blinkTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    guard let self, let button = self.statusItem?.button else { return }
                    self.blinkVisible.toggle()
                    button.appearsDisabled = !self.blinkVisible
                }
            }
        } else {
            statusItem?.button?.appearsDisabled = false
        }
    }
}

// MARK: - Popover Content

struct MenuBarPopoverView: View {
    @ObservedObject var timerManager: TimerManager
    @ObservedObject var presetStore: PresetStore
    @ObservedObject var reminderStore = ReminderStore.shared
    let dismiss: () -> Void

    @State private var customMinutes: String = ""
    @State private var noteText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            remindersSection

            if timerManager.timerState == .idle {
                idleContent
            } else {
                runningContent
            }

            Button {
                dismiss()
                NSApp.activate(ignoringOtherApps: true)
                for window in NSApp.windows where window.canBecomeKey && !window.isReminderWindow {
                    window.makeKeyAndOrderFront(nil)
                    return
                }
            } label: {
                Text(L("打开 Tick", "Open Tick"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Button {
                LanguageStore.shared.toggle()
                dismiss()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "globe")
                        .font(.system(size: 11))
                    Text(L("Switch to English", "切换到中文"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Button {
                NSApp.terminate(nil)
            } label: {
                HStack {
                    Text(L("退出 Tick", "Quit Tick"))
                    Spacer()
                    Text("⌘Q")
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
        }
        .padding(.vertical, 8)
        .frame(width: 220)
    }

    private var remindersSection: some View {
        VStack(spacing: 0) {
            ForEach(reminderStore.reminders.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) { reminder in
                HStack(spacing: 6) {
                    Text(reminder.timeLabel)
                        .font(.system(size: 12, weight: .medium).monospacedDigit())
                    Text(reminder.note.isEmpty ? reminder.daysSummary() : reminder.note)
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                    Spacer()
                    Toggle("", isOn: Binding(
                        get: { reminder.isEnabled },
                        set: { isOn in
                            guard let index = reminderStore.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
                            reminderStore.reminders[index].isEnabled = isOn && !reminderStore.reminders[index].weekdays.isEmpty
                        }
                    ))
                    .labelsHidden()
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 3)
                .opacity(reminder.isEnabled ? 1 : 0.55)
            }

            Button {
                dismiss()
                VoiceReminderController.shared.beginListening()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "mic")
                        .font(.system(size: 11))
                    Text(L("语音添加提醒", "Add by Voice…"))
                    Spacer()
                    Text(VoiceReminderController.shared.hotKeyCombo.label)
                        .foregroundColor(.secondary)
                        .font(.system(size: 12))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Button {
                dismiss()
                ReminderWindow.shared.show()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "moon")
                        .font(.system(size: 11))
                    Text(reminderStore.reminders.isEmpty ? L("添加每日提醒…", "Add Daily Reminder…") : L("管理提醒…", "Manage Reminders…"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)

            Divider()
                .padding(.vertical, 4)
        }
    }

    private var idleContent: some View {
        VStack(spacing: 0) {
            if timerManager.hasLastTimer {
                Button {
                    timerManager.repeatLast()
                    dismiss()
                } label: {
                    HStack {
                        Image(systemName: "arrow.counterclockwise")
                            .font(.system(size: 11))
                        Text(L("重复上次", "Repeat Last"))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)

                Divider()
                    .padding(.vertical, 4)
            }

            ForEach(presetStore.presets) { preset in
                Button {
                    timerManager.start(minutes: preset.minutes, seconds: 0, note: noteText)
                    noteText = ""
                    dismiss()
                } label: {
                    Text(L("开始 \(preset.displayLabel)", "Start \(preset.displayLabel)"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Divider()
                .padding(.vertical, 4)

            HStack {
                TextField(L("备注（可选）", "Note (optional)"), text: $noteText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 12))
                    .frame(width: 120)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 4)

            HStack(spacing: 8) {
                TextField(L("自定义", "Custom"), text: $customMinutes)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 70)
                    .multilineTextAlignment(.center)
                    .onChange(of: customMinutes) { newValue in
                        // isNumber alone would accept full-width "５" from Chinese IMEs, which Int() rejects
                        let digits = newValue.filter { $0.isASCII && $0.isNumber }
                        customMinutes = (Int(digits) ?? 0) > 999 ? "999" : digits
                    }
                    .onSubmit {
                        if let mins = Int(customMinutes), mins > 0 {
                            timerManager.start(minutes: mins, seconds: 0, note: noteText)
                            customMinutes = ""
                            noteText = ""
                            dismiss()
                        }
                    }

                Text(L("分钟", "min"))
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))

                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
                .padding(.vertical, 4)
        }
    }

    private var runningContent: some View {
        VStack(spacing: 0) {
            if !timerManager.note.isEmpty {
                Text(timerManager.note)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 6)

                Divider()
                    .padding(.vertical, 4)
            }

            if timerManager.timerState == .running {
                Button {
                    timerManager.pause()
                    dismiss()
                } label: {
                    Text(L("暂停", "Pause"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            } else {
                Button {
                    timerManager.resume()
                    dismiss()
                } label: {
                    Text(L("继续", "Resume"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }

            Button {
                timerManager.cancel()
                dismiss()
            } label: {
                Text(L("取消", "Cancel"))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            Divider()
                .padding(.vertical, 4)
        }
    }
}
