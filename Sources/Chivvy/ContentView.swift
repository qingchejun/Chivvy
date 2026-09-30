import ServiceManagement
import SwiftUI

struct ContentView: View {
    @ObservedObject private var timer = TimerManager.shared
    @ObservedObject private var presetStore = PresetStore.shared
    @ObservedObject private var reminderScheduler = ReminderScheduler.shared

    @State private var inputMinutes: String = ""
    @State private var inputSeconds: String = ""
    @State private var inputNote: String = ""
    @State private var alwaysOnTop = UserDefaults.standard.bool(forKey: "alwaysOnTop")
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showPresetEditor = false

    var body: some View {
        VStack(spacing: 0) {
            // Top toolbar
            HStack {
                Button {
                    launchAtLogin.toggle()
                    do {
                        if launchAtLogin {
                            try SMAppService.mainApp.register()
                        } else {
                            try SMAppService.mainApp.unregister()
                        }
                    } catch {
                        launchAtLogin.toggle()
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: launchAtLogin ? "sunrise.fill" : "sunrise")
                            .font(.system(size: 12, weight: .medium))
                        Text(L("开机自启", "Auto-start"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(launchAtLogin ? .orange : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(launchAtLogin ? Color.orange.opacity(0.12) : Color.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help(L("登录时自动启动", "Launch at login"))

                Spacer()

                reminderButton

                languageButton

                Button {
                    alwaysOnTop.toggle()
                    UserDefaults.standard.set(alwaysOnTop, forKey: "alwaysOnTop")
                    setWindowLevel(alwaysOnTop ? .floating : .normal)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                            .font(.system(size: 12, weight: .medium))
                        Text(alwaysOnTop ? L("已置顶", "Pinned") : L("置顶", "Pin"))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundColor(alwaysOnTop ? .accentColor : .secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(alwaysOnTop ? Color.accentColor.opacity(0.12) : Color.secondary.opacity(0.08))
                    )
                }
                .buttonStyle(.plain)
                .help(L("窗口置顶", "Keep window on top"))
            }
            .padding(.top, 8)
            .padding(.horizontal, 20)

            Spacer()

            // Progress ring
            CircularProgressView(
                progress: timer.progress,
                timeString: timer.timerState == .idle ? idleTimeString : timer.formattedTime,
                timerState: timer.timerState,
                completionCount: timer.completionCount
            )

            Spacer()

            // Controls section
            VStack(spacing: 20) {
                presetButtons

                if timer.timerState == .idle {
                    noteInput
                    customInput
                } else if !timer.note.isEmpty {
                    Text(timer.note)
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                controlButtons

                Text(shortcutHint)
                    .font(.system(size: 10))
                    .foregroundStyle(.quaternary)
                    .opacity(shortcutHintVisible ? 1 : 0)
            }
            .padding(.bottom, 32)
        }
        .frame(width: 380, height: 490)
        .background(KeyEventHandler(
            onSpace: handleSpace,
            onEscape: handleEscape,
            onReturn: handleReturn
        ))
        .onAppear {
            if alwaysOnTop {
                setWindowLevel(.floating)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            // Auto-start can also be turned on from the Reminders window
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .sheet(isPresented: $showPresetEditor) {
            PresetEditorView(store: presetStore)
        }
    }

    // MARK: - Reminder Button

    private var reminderButton: some View {
        let upcoming = reminderScheduler.upcoming
        return Button {
            ReminderWindow.shared.show()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: upcoming != nil ? "moon.fill" : "moon")
                    .font(.system(size: 12, weight: .medium))
                Text(upcoming?.reminder.timeLabel ?? L("提醒", "Reminders"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(upcoming != nil ? .indigo : .secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(upcoming != nil ? Color.indigo.opacity(0.12) : Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(L("每日弹窗提醒", "Daily pop-up reminders"))
    }

    // MARK: - Language Button

    /// Shows the language it switches to, so it's findable by someone who can't read the current one
    private var languageButton: some View {
        Button {
            LanguageStore.shared.toggle()
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "globe")
                    .font(.system(size: 12, weight: .medium))
                Text(L("EN", "中文"))
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundColor(.secondary)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(Color.secondary.opacity(0.08))
            )
        }
        .buttonStyle(.plain)
        .help(L("Switch to English", "切换到中文"))
    }

    // MARK: - Preset Buttons

    @State private var selectedPreset: TimerPreset?

    private var presetButtons: some View {
        HStack(spacing: 10) {
            ForEach(presetStore.presets) { preset in
                Button(preset.displayLabel) {
                    selectedPreset = preset
                    inputMinutes = String(preset.minutes)
                    inputSeconds = "0"
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(selectedPreset?.id == preset.id ? .accentColor : nil)
                .disabled(timer.timerState != .idle)
            }

            Button {
                showPresetEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12))
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(timer.timerState != .idle)
            .help(L("编辑预设", "Edit presets"))
        }
    }

    // MARK: - Note Input

    private var noteInput: some View {
        TextField(L("备注（可选）", "Note (optional)"), text: $inputNote)
            .textFieldStyle(.roundedBorder)
            .frame(width: 130)
            .multilineTextAlignment(.center)
            .font(.system(size: 13))
            .onSubmit { handleReturn() }
    }

    // MARK: - Custom Input

    private var customInput: some View {
        HStack(spacing: 8) {
            TextField("00", text: $inputMinutes)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .multilineTextAlignment(.center)
                .onChange(of: inputMinutes) { newValue in
                    inputMinutes = filterNumericInput(newValue, max: 999)
                }
                .onSubmit { handleReturn() }

            Text(":")
                .font(.title3)
                .foregroundStyle(.tertiary)

            TextField("00", text: $inputSeconds)
                .textFieldStyle(.roundedBorder)
                .frame(width: 56)
                .multilineTextAlignment(.center)
                .onChange(of: inputSeconds) { newValue in
                    inputSeconds = filterNumericInput(newValue, max: 59)
                }
                .onSubmit { handleReturn() }
        }
    }

    // MARK: - Control Buttons

    private var controlButtons: some View {
        HStack(spacing: 14) {
            switch timer.timerState {
            case .idle:
                if timer.hasLastTimer {
                    Button(L("重复", "Repeat")) {
                        timer.repeatLast()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                    .help(L("重复 \(timer.lastMinutes) 分\(timer.lastSeconds > 0 ? " \(timer.lastSeconds) 秒" : "")",
                             "Repeat \(timer.lastMinutes) min\(timer.lastSeconds > 0 ? " \(timer.lastSeconds) sec" : "")"))
                }

                Button(L("开始", "Start")) {
                    startFromInput()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .disabled(!hasValidCustomInput)
                .help("⏎ Return")

            case .running:
                Button(L("暂停", "Pause")) {
                    timer.pause()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .help("␣ Space")

                Button(L("取消", "Cancel")) {
                    timer.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .help("⎋ Escape")

            case .paused:
                Button(L("继续", "Resume")) {
                    timer.resume()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .help("␣ Space")

                Button(L("取消", "Cancel")) {
                    timer.cancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .tint(.red)
                .help("⎋ Escape")
            }
        }
    }

    // MARK: - Helpers

    private var shortcutHintVisible: Bool {
        timer.timerState != .idle || hasValidCustomInput
    }

    private var shortcutHint: String {
        if timer.timerState != .idle {
            return L("Space 暂停/继续 · Esc 取消", "Space pause/resume · Esc cancel")
        }
        return L("Return 开始", "Press Return to start")
    }

    private var idleTimeString: String {
        let mins = Int(inputMinutes) ?? 0
        let secs = Int(inputSeconds) ?? 0
        return String(format: "%02d:%02d", mins, secs)
    }

    private var hasValidCustomInput: Bool {
        let mins = Int(inputMinutes) ?? 0
        let secs = Int(inputSeconds) ?? 0
        return (mins * 60 + secs) > 0
    }

    private func startFromInput() {
        let mins = Int(inputMinutes) ?? 0
        let secs = Int(inputSeconds) ?? 0
        timer.start(minutes: mins, seconds: secs, note: inputNote)
        inputMinutes = ""
        inputSeconds = ""
        inputNote = ""
        selectedPreset = nil
    }

    private func filterNumericInput(_ value: String, max: Int) -> String {
        // isNumber alone would accept full-width "５" from Chinese IMEs, which Int() rejects
        let filtered = value.filter { $0.isASCII && $0.isNumber }
        if let num = Int(filtered), num > max {
            return String(max)
        }
        return filtered
    }

    private func setWindowLevel(_ level: NSWindow.Level) {
        for window in NSApp.windows where window.canBecomeKey && !(window is NSPanel) && !window.isReminderWindow {
            window.level = level
        }
    }

    // MARK: - Keyboard Handlers

    private func handleSpace() {
        switch timer.timerState {
        case .running: timer.pause()
        case .paused: timer.resume()
        case .idle: break
        }
    }

    private func handleEscape() {
        if timer.timerState != .idle {
            timer.cancel()
        }
    }

    private func handleReturn() {
        if timer.timerState == .idle && hasValidCustomInput {
            startFromInput()
        }
    }
}

// MARK: - Language Root

/// Rebuilds its content when the UI language changes, so every nested L(...) is re-read
struct LanguageRoot<Content: View>: View {
    @ObservedObject private var languages = LanguageStore.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        content().id(languages.language)
    }
}

// MARK: - Preset Editor

struct PresetEditorView: View {
    @ObservedObject var store: PresetStore
    @Environment(\.dismiss) private var dismiss

    @State private var editingPresets: [TimerPreset] = []
    @State private var newLabel: String = ""
    @State private var newMinutes: String = ""

    var body: some View {
        VStack(spacing: 16) {
            Text(L("编辑预设", "Edit presets"))
                .font(.headline)

            List {
                ForEach($editingPresets) { $preset in
                    HStack(spacing: 12) {
                        TextField(L("名称", "Name"), text: $preset.label)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)

                        TextField(L("分钟", "min"), text: Binding(
                            get: { String(preset.minutes) },
                            set: { preset.minutes = Int($0).map { min(max($0, 1), 999) } ?? preset.minutes }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)

                        Text(L("分钟", "min"))
                            .foregroundStyle(.secondary)
                            .font(.system(size: 12))

                        Spacer()

                        Button {
                            editingPresets.removeAll { $0.id == preset.id }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .onMove { from, to in
                    editingPresets.move(fromOffsets: from, toOffset: to)
                }
            }
            .frame(height: 160)

            if editingPresets.count < TimerPreset.maxCount {
                HStack(spacing: 8) {
                    TextField(L("名称", "Name"), text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)

                    TextField(L("分钟", "min"), text: $newMinutes)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 50)
                        .multilineTextAlignment(.center)

                    Button(L("添加", "Add")) {
                        if let mins = Int(newMinutes), mins > 0, !newLabel.isEmpty {
                            editingPresets.append(TimerPreset(label: newLabel, minutes: min(mins, 999)))
                            newLabel = ""
                            newMinutes = ""
                        }
                    }
                    .disabled(newLabel.isEmpty || Int(newMinutes) ?? 0 <= 0)
                }
            }

            HStack(spacing: 12) {
                Button(L("恢复默认", "Restore Defaults")) {
                    editingPresets = TimerPreset.builtIn
                }
                .foregroundStyle(.secondary)

                Spacer()

                Button(L("取消", "Cancel")) {
                    dismiss()
                }

                Button(L("保存", "Save")) {
                    store.presets = editingPresets
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(editingPresets.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 340)
        .onAppear {
            // Show auto-generated labels ("25 分钟" / "25 min") in the current language
            editingPresets = store.presets.map { preset in
                var preset = preset
                preset.label = preset.displayLabel
                return preset
            }
        }
    }
}

// MARK: - Key Event Handler

struct KeyEventHandler: NSViewRepresentable {
    let onSpace: () -> Void
    let onEscape: () -> Void
    let onReturn: () -> Void

    func makeNSView(context: Context) -> KeyCaptureView {
        let view = KeyCaptureView()
        view.onSpace = onSpace
        view.onEscape = onEscape
        view.onReturn = onReturn
        return view
    }

    func updateNSView(_ nsView: KeyCaptureView, context: Context) {
        nsView.onSpace = onSpace
        nsView.onEscape = onEscape
        nsView.onReturn = onReturn
    }
}

class KeyCaptureView: NSView {
    var onSpace: (() -> Void)?
    var onEscape: (() -> Void)?
    var onReturn: (() -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 49: // Space
            onSpace?()
        case 53: // Escape
            onEscape?()
        case 36: // Return
            onReturn?()
        default:
            super.keyDown(with: event)
        }
    }
}
