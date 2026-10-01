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

    /// The app icon's "C" ring with its alert dot, as a template image so it follows the menu bar's color
    private static let statusIcon: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let center = NSPoint(x: 8.5, y: 9)
            let radius: CGFloat = 6.25
            let ring = NSBezierPath()
            ring.appendArc(withCenter: center, radius: radius, startAngle: 45, endAngle: 315)
            ring.lineWidth = 2.3
            ring.lineCapStyle = .round
            NSColor.black.setStroke()
            ring.stroke()
            let dot: CGFloat = 2.3
            NSColor.black.setFill()
            NSBezierPath(ovalIn: NSRect(x: center.x + radius - dot, y: center.y - dot, width: dot * 2, height: dot * 2)).fill()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Chivvy"
        return image
    }()

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        if let button = statusItem?.button {
            button.image = Self.statusIcon
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
        pop.contentSize = NSSize(width: MenuBarPopoverView.width, height: 0)
        let timerManager = timerManager
        pop.contentViewController = NSHostingController(
            rootView: LanguageRoot {
                MenuBarPopoverView(timerManager: timerManager, presetStore: PresetStore.shared) { [weak pop] in
                    pop?.performClose(nil)
                }
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
            button.image = Self.statusIcon
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
    static let width: CGFloat = 288

    @ObservedObject var timerManager: TimerManager
    @ObservedObject var presetStore: PresetStore
    @ObservedObject var reminderStore = ReminderStore.shared
    @ObservedObject var voice = VoiceReminderController.shared
    let dismiss: () -> Void

    @State private var customMinutes: String = ""
    @State private var noteText: String = ""

    private var sortedReminders: [DailyReminder] {
        reminderStore.reminders.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if timerManager.timerState != .idle {
                runningCard
            }

            remindersSection

            if timerManager.timerState == .idle {
                separator
                quickStart
            }

            separator
            footer
        }
        .padding(6)
        .frame(width: Self.width)
        .tint(Theme.brand)
    }

    private var separator: some View {
        Rectangle()
            .fill(Theme.separator.opacity(0.7))
            .frame(height: 1)
            .padding(.horizontal, 10)
            .padding(.vertical, Theme.Space.xs)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 10)
            .padding(.top, 6)
            .padding(.bottom, 2)
    }

    // MARK: Running

    private var runningCard: some View {
        VStack(alignment: .leading, spacing: Theme.Space.s) {
            HStack(alignment: .firstTextBaseline) {
                Text(timerManager.note.isEmpty
                     ? (timerManager.timerState == .paused ? L("已暂停", "Paused") : L("倒计时", "Countdown"))
                     : timerManager.note)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)
                Spacer()
                Text(timerManager.formattedTime)
                    .font(.system(size: 28, weight: .light).monospacedDigit())
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.fillStrong)
                    Capsule().fill(Theme.brand)
                        .frame(width: proxy.size.width * timerManager.progress)
                }
            }
            .frame(height: 4)
            HStack(spacing: 6) {
                if timerManager.timerState == .running {
                    Button(L("暂停", "Pause")) { timerManager.pause(); dismiss() }
                        .buttonStyle(.chivvy(.secondary, size: .small, fill: true))
                } else {
                    Button(L("继续", "Resume")) { timerManager.resume(); dismiss() }
                        .buttonStyle(.chivvy(.primary, size: .small, fill: true))
                }
                Button(L("取消", "Cancel")) { timerManager.cancel(); dismiss() }
                    .buttonStyle(.chivvy(.danger, size: .small, fill: true))
            }
        }
        .padding(.horizontal, Theme.Space.m)
        .padding(.vertical, 10)
        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
        .padding(.bottom, Theme.Space.xs)
    }

    // MARK: Reminders

    private var remindersSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            if !sortedReminders.isEmpty {
                sectionTitle(L("提醒", "Reminders"))
                ForEach(sortedReminders) { reminder in
                    reminderRow(reminder)
                }
            }

            Button {
                dismiss()
                voice.beginListening()
            } label: {
                HStack(spacing: Theme.Space.s) {
                    rowIcon("mic")
                    Text(L("语音添加…", "Add by Voice…"))
                    Spacer()
                    Keycap(text: voice.hotKeyCombo.label)
                }
            }
            .buttonStyle(.hoverRow)

            Button {
                dismiss()
                MainWindowRouter.shared.open(.reminders)
            } label: {
                HStack(spacing: Theme.Space.s) {
                    rowIcon("bell")
                    Text(reminderStore.reminders.isEmpty ? L("添加提醒…", "Add Reminder…") : L("管理提醒…", "Manage Reminders…"))
                }
            }
            .buttonStyle(.hoverRow)
        }
    }

    private func reminderRow(_ reminder: DailyReminder) -> some View {
        HoverRow {
            HStack(spacing: 10) {
                Group {
                    Text(reminder.timeLabel)
                        .font(.system(size: 13, weight: .semibold).monospacedDigit())
                    Text(reminder.note.isEmpty ? reminder.daysSummary() : reminder.note)
                        .lineLimit(1)
                }
                .opacity(reminder.isEnabled ? 1 : 0.45)
                Spacer(minLength: Theme.Space.xs)
                if reminder.isEnabled, let next = reminder.nextFireDate(after: Date()) {
                    Text(DailyReminder.whenLabel(next))
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }
                Toggle("\(reminder.timeLabel) \(reminder.note)", isOn: Binding(
                    get: { reminder.isEnabled },
                    set: { isOn in
                        guard let index = reminderStore.reminders.firstIndex(where: { $0.id == reminder.id }) else { return }
                        reminderStore.reminders[index].isEnabled = isOn && reminderStore.reminders[index].canFire()
                    }
                ))
                .labelsHidden()
                .toggleStyle(.brandSwitchSmall)
            }
        }
    }

    private func rowIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 12))
            .foregroundStyle(.secondary)
            .frame(width: 16)
    }

    // MARK: Quick start

    private var quickStart: some View {
        VStack(alignment: .leading, spacing: 2) {
            sectionTitle(L("快速开始", "Quick start"))

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: min(max(presetStore.presets.count, 1), 4)),
                      spacing: 6) {
                ForEach(presetStore.presets) { preset in
                    Button(preset.shortLabel) {
                        timerManager.start(minutes: preset.minutes, seconds: 0, note: noteText)
                        noteText = ""
                        dismiss()
                    }
                    .buttonStyle(.chivvy(.secondary, size: .regular, fill: true))
                    .help(L("开始 \(preset.displayLabel)", "Start \(preset.displayLabel)"))
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)

            if timerManager.hasLastTimer {
                Button {
                    timerManager.repeatLast()
                    dismiss()
                } label: {
                    HStack(spacing: Theme.Space.s) {
                        rowIcon("arrow.counterclockwise")
                        Text(L("重复上次", "Repeat Last"))
                        Spacer()
                        Text(lastTimerSummary)
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .buttonStyle(.hoverRow)
            }

            HStack(spacing: 6) {
                TextField(L("备注", "Note"), text: $noteText)
                    .textFieldStyle(.roundedBorder)
                TextField(L("分钟", "min"), text: $customMinutes)
                    .textFieldStyle(.roundedBorder)
                    .multilineTextAlignment(.center)
                    .frame(width: 52)
                    .onChange(of: customMinutes) { newValue in
                        // isNumber alone would accept full-width "５" from Chinese IMEs, which Int() rejects
                        let digits = newValue.filter { $0.isASCII && $0.isNumber }
                        customMinutes = (Int(digits) ?? 0) > 999 ? "999" : digits
                    }
                    .onSubmit(startCustom)
                Button(L("开始", "Start"), action: startCustom)
                    .buttonStyle(.chivvy(.primary, size: .small))
                    .disabled((Int(customMinutes) ?? 0) <= 0)
            }
            .font(.system(size: 12))
            .padding(.horizontal, 6)
            .padding(.vertical, Theme.Space.xs)
        }
    }

    private var lastTimerSummary: String {
        let duration = durationLabel(timerManager.lastMinutes * 60 + timerManager.lastSeconds)
        return timerManager.lastNote.isEmpty ? duration : "\(duration) · \(timerManager.lastNote)"
    }

    private func startCustom() {
        guard let mins = Int(customMinutes), mins > 0 else { return }
        timerManager.start(minutes: mins, seconds: 0, note: noteText)
        customMinutes = ""
        noteText = ""
        dismiss()
    }

    // MARK: Footer

    private var footer: some View {
        HStack(spacing: 2) {
            Button {
                dismiss()
                MainWindowRouter.shared.open()
            } label: {
                HStack(spacing: Theme.Space.s) {
                    rowIcon("macwindow")
                    Text(L("打开 Chivvy", "Open Chivvy"))
                }
            }
            .buttonStyle(.hoverRow)

            Button {
                LanguageStore.shared.toggle()
                dismiss()
            } label: {
                Label(L("EN", "中文"), systemImage: "globe")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, Theme.Space.s)
                    .frame(height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("Switch to English", "切换到中文"))

            Button {
                NSApp.terminate(nil)
            } label: {
                Image(systemName: "power")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
                    .frame(width: 28, height: 28)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .keyboardShortcut("q")
            .help(L("退出 Chivvy (⌘Q)", "Quit Chivvy (⌘Q)"))
            .accessibilityLabel(L("退出 Chivvy", "Quit Chivvy"))
        }
    }
}
