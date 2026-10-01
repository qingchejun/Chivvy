import AppKit
import SwiftUI

// MARK: - Countdown Pane

/// What's typed into the countdown pane. A reference type so the key monitor sees current values.
@MainActor
private final class TimerInput: ObservableObject {
    @Published var minutes = ""
    @Published var seconds = ""
    @Published var note = ""
    @Published var selectedPreset: UUID?

    var totalSeconds: Int { (Int(minutes) ?? 0) * 60 + (Int(seconds) ?? 0) }
    var isValid: Bool { totalSeconds > 0 }

    var timeString: String {
        String(format: "%02d:%02d", Int(minutes) ?? 0, Int(seconds) ?? 0)
    }

    func clear() {
        minutes = ""
        seconds = ""
        note = ""
        selectedPreset = nil
    }
}

struct TimerPane: View {
    @ObservedObject private var timer = TimerManager.shared
    @ObservedObject private var presetStore = PresetStore.shared
    @StateObject private var input = TimerInput()
    @AppStorage(MainWindowRouter.alwaysOnTopKey) private var alwaysOnTop = false

    @State private var showPresetEditor = false
    @State private var keyMonitor: Any?

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: MainSection.timer.title) {
                pinButton
            }

            VStack(spacing: 18) {
                CircularProgressView(
                    progress: timer.timerState == .idle ? 1 : timer.progress,
                    timeString: timer.timerState == .idle ? input.timeString : timer.formattedTime,
                    caption: ringCaption,
                    timerState: timer.timerState,
                    completionCount: timer.completionCount
                )

                presetRow

                if timer.timerState == .idle {
                    inputRow
                } else {
                    statusRow
                }

                controlButtons

                Text(shortcutHint)
                    .font(Theme.Font.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, Theme.Space.xxl)
            .padding(.bottom, 20)
            .frame(maxHeight: .infinity)
        }
        .onAppear(perform: installKeyMonitor)
        .onDisappear(perform: removeKeyMonitor)
        .sheet(isPresented: $showPresetEditor) {
            PresetEditorView(store: presetStore)
        }
    }

    // MARK: Header

    private var pinButton: some View {
        Button {
            alwaysOnTop.toggle()
            MainWindowRouter.shared.applyPin()
        } label: {
            Image(systemName: alwaysOnTop ? "pin.fill" : "pin")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(alwaysOnTop ? Theme.brandText : Color.secondary)
                .frame(width: 28, height: 28)
                .background(alwaysOnTop ? Theme.brandSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(alwaysOnTop ? L("取消置顶", "Unpin window") : L("窗口置顶", "Keep window on top"))
        .accessibilityLabel(L("窗口置顶", "Keep window on top"))
        .accessibilityValue(alwaysOnTop ? L("开", "On") : L("关", "Off"))
    }

    // MARK: Ring

    private var ringCaption: String {
        switch timer.timerState {
        case .idle:
            return input.isValid ? L("准备好了", "Ready") : L("选个预设，或输入时间", "Pick a preset or enter a time")
        case .running:
            return timer.note.isEmpty ? L("进行中", "Running") : timer.note
        case .paused:
            return L("已暂停", "Paused")
        }
    }

    // MARK: Presets

    private var presetRow: some View {
        HStack(spacing: 6) {
            SegmentedChips(
                items: presetStore.presets.map(\.id),
                selection: input.selectedPreset,
                label: { id in presetStore.presets.first { $0.id == id }?.displayLabel ?? "" },
                onSelect: { id in
                    guard let preset = presetStore.presets.first(where: { $0.id == id }) else { return }
                    input.selectedPreset = id
                    input.minutes = String(preset.minutes)
                    input.seconds = "0"
                }
            )
            Button {
                showPresetEditor = true
            } label: {
                Image(systemName: "pencil")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("编辑预设", "Edit presets"))
            .accessibilityLabel(L("编辑预设", "Edit presets"))
        }
        .disabled(timer.timerState != .idle)
        .opacity(timer.timerState == .idle ? 1 : 0.4)
    }

    // MARK: Input

    private var inputRow: some View {
        HStack(spacing: Theme.Space.m) {
            TextField(L("备注（可选）", "Note (optional)"), text: $input.note)
                .textFieldStyle(.roundedBorder)
                .frame(width: 180)
                .onSubmit(startIfValid)

            HStack(spacing: Theme.Space.xs) {
                numberField($input.minutes, max: 999)
                Text(":")
                    .foregroundStyle(.secondary)
                numberField($input.seconds, max: 59)
            }
        }
        .font(Theme.Font.body)
    }

    private func numberField(_ text: Binding<String>, max: Int) -> some View {
        TextField("00", text: text)
            .textFieldStyle(.roundedBorder)
            .multilineTextAlignment(.center)
            .monospacedDigit()
            .frame(width: 44)
            .onChange(of: text.wrappedValue) { newValue in
                text.wrappedValue = Self.filterNumericInput(newValue, max: max)
                input.selectedPreset = nil
            }
            .onSubmit(startIfValid)
    }

    /// While running, the input row's slot shows when the countdown will end
    private var statusRow: some View {
        HStack(spacing: Theme.Space.xs) {
            if timer.timerState == .running, let end = timer.endDate {
                Text(L("结束于", "Ends at"))
                    .foregroundStyle(.secondary)
                Text(end, format: .dateTime.hour(.twoDigits(amPM: .omitted)).minute(.twoDigits))
                    .monospacedDigit()
            } else {
                Text(L("已暂停，随时继续", "Paused. Resume any time."))
                    .foregroundStyle(.secondary)
            }
        }
        .font(.system(size: 12))
        .frame(height: 28)
    }

    // MARK: Controls

    private var controlButtons: some View {
        HStack(spacing: 10) {
            switch timer.timerState {
            case .idle:
                if timer.hasLastTimer {
                    Button {
                        timer.repeatLast()
                    } label: {
                        Label(L("重复上次", "Repeat Last"), systemImage: "arrow.counterclockwise")
                    }
                    .buttonStyle(.chivvy(.secondary, size: .large))
                    .help(durationLabel(timer.lastMinutes * 60 + timer.lastSeconds)
                          + (timer.lastNote.isEmpty ? "" : " · \(timer.lastNote)"))
                }
                Button(action: startIfValid) {
                    Text(L("开始", "Start"))
                        .frame(minWidth: 100)
                }
                .buttonStyle(.chivvy(.primary, size: .large))
                .disabled(!input.isValid)

            case .running:
                Button(L("取消", "Cancel")) { timer.cancel() }
                    .buttonStyle(.chivvy(.danger, size: .large))
                Button {
                    timer.pause()
                } label: {
                    Label(L("暂停", "Pause"), systemImage: "pause.fill")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.chivvy(.secondary, size: .large))

            case .paused:
                Button(L("取消", "Cancel")) { timer.cancel() }
                    .buttonStyle(.chivvy(.danger, size: .large))
                Button {
                    timer.resume()
                } label: {
                    Label(L("继续", "Resume"), systemImage: "play.fill")
                        .frame(minWidth: 100)
                }
                .buttonStyle(.chivvy(.primary, size: .large))
            }
        }
    }

    private var shortcutHint: String {
        switch timer.timerState {
        case .idle: return input.isValid ? L("回车 开始", "Return to start") : " "
        case .running: return L("空格 暂停 · Esc 取消", "Space to pause · Esc to cancel")
        case .paused: return L("空格 继续 · Esc 取消", "Space to resume · Esc to cancel")
        }
    }

    // MARK: Actions

    private func startIfValid() {
        guard timer.timerState == .idle, input.isValid else { return }
        let total = input.totalSeconds
        timer.start(minutes: total / 60, seconds: total % 60, note: input.note)
        input.clear()
    }

    static func filterNumericInput(_ value: String, max: Int) -> String {
        // isNumber alone would accept full-width "５" from Chinese IMEs, which Int() rejects
        let filtered = value.filter { $0.isASCII && $0.isNumber }
        if let num = Int(filtered), num > max {
            return String(max)
        }
        return filtered
    }

    // MARK: Keyboard

    /// Space / Esc / Return drive the countdown while this pane shows, unless a text field is being edited
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        let timer = self.timer
        let input = self.input
        let start = startIfValid
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard let window = event.window,
                  MainWindowRouter.shared.isMainWindow(window),
                  window.attachedSheet == nil,
                  event.modifierFlags.intersection([.command, .control, .option]).isEmpty else { return event }
            let editingText = window.firstResponder is NSTextView
            switch event.keyCode {
            case 49 where !editingText: // Space
                switch timer.timerState {
                case .running: timer.pause()
                case .paused: timer.resume()
                case .idle: return event
                }
                return nil
            case 53 where timer.timerState != .idle: // Escape
                timer.cancel()
                return nil
            case 36 where !editingText && input.isValid && timer.timerState == .idle: // Return
                start()
                return nil
            default:
                return event
            }
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
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
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(L("编辑预设", "Edit presets"))
                .font(Theme.Font.headline)

            List {
                ForEach($editingPresets) { $preset in
                    HStack(spacing: Theme.Space.s) {
                        TextField(L("名称", "Name"), text: $preset.label)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 110)

                        TextField(L("分钟", "min"), text: Binding(
                            get: { String(preset.minutes) },
                            set: { preset.minutes = Int($0).map { min(max($0, 1), 999) } ?? preset.minutes }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .monospacedDigit()
                        .frame(width: 50)

                        Text(L("分钟", "min"))
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)

                        Spacer()

                        Button {
                            editingPresets.removeAll { $0.id == preset.id }
                        } label: {
                            Image(systemName: "minus.circle")
                                .foregroundStyle(Theme.danger)
                        }
                        .buttonStyle(.plain)
                        .help(L("删除", "Delete"))
                    }
                    .padding(.vertical, 2)
                }
                .onMove { from, to in
                    editingPresets.move(fromOffsets: from, toOffset: to)
                }
            }
            .frame(height: 170)
            .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
            .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.separator.opacity(0.6)))

            if editingPresets.count < TimerPreset.maxCount {
                HStack(spacing: Theme.Space.s) {
                    TextField(L("名称", "Name"), text: $newLabel)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 110)

                    TextField(L("分钟", "min"), text: $newMinutes)
                        .textFieldStyle(.roundedBorder)
                        .multilineTextAlignment(.center)
                        .frame(width: 50)

                    Button(L("添加", "Add")) {
                        if let mins = Int(newMinutes), mins > 0, !newLabel.isEmpty {
                            editingPresets.append(TimerPreset(label: newLabel, minutes: min(mins, 999)))
                            newLabel = ""
                            newMinutes = ""
                        }
                    }
                    .buttonStyle(.chivvy(.secondary))
                    .disabled(newLabel.isEmpty || Int(newMinutes) ?? 0 <= 0)
                }
            }

            HStack(spacing: Theme.Space.s) {
                Button(L("恢复默认", "Restore Defaults")) {
                    editingPresets = TimerPreset.builtIn
                }
                .buttonStyle(.chivvy(.text))

                Spacer()

                Button(L("取消", "Cancel")) { dismiss() }
                    .buttonStyle(.chivvy(.secondary))
                    .keyboardShortcut(.cancelAction)

                Button(L("保存", "Save")) {
                    store.presets = editingPresets
                    dismiss()
                }
                .buttonStyle(.chivvy(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(editingPresets.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 360)
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
