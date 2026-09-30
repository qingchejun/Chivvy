import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Window

/// Standalone window for managing all daily reminders, openable from the main window and menu bar
@MainActor
final class ReminderWindow {
    static let shared = ReminderWindow()
    static let identifier = NSUserInterfaceItemIdentifier("reminders")

    private var window: NSWindow?

    func show() {
        if window == nil {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 460, height: 520),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            window.identifier = Self.identifier
            window.title = "提醒"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: ReminderManagerView(store: .shared, scheduler: .shared)
            )
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}

extension NSWindow {
    /// The Reminders window is a secondary window; code looking for "the" Tick window skips it
    var isReminderWindow: Bool { identifier == ReminderWindow.identifier }
}

// MARK: - Manager

struct ReminderManagerView: View {
    @ObservedObject var store: ReminderStore
    @ObservedObject var scheduler: ReminderScheduler

    @State private var selection = Set<UUID>()
    @State private var editing: DailyReminder?
    @State private var confirmingDelete = false
    @State private var loginStatus = SMAppService.mainApp.status

    private var enabledCount: Int { store.reminders.filter(\.isEnabled).count }

    /// Batch actions apply to the selection, or to everything when nothing is selected
    private var targetIDs: Set<UUID> {
        selection.isEmpty ? Set(store.reminders.map(\.id)) : selection
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.reminders.isEmpty {
                emptyState
            } else {
                list
            }

            Divider()
            footer
        }
        .frame(minWidth: 440, minHeight: 420)
        .sheet(item: $editing) { reminder in
            ReminderEditSheet(
                reminder: reminder,
                isNew: !store.reminders.contains { $0.id == reminder.id }
            ) { saved in
                if let index = store.reminders.firstIndex(where: { $0.id == saved.id }) {
                    store.reminders[index] = saved
                } else {
                    store.reminders.append(saved)
                }
            }
        }
        .confirmationDialog(
            selection.isEmpty
                ? "删除全部 \(targetIDs.count) 条提醒？"
                : "删除 \(targetIDs.count) 条提醒？",
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button("删除", role: .destructive) {
                let ids = targetIDs
                store.reminders.removeAll { ids.contains($0.id) }
                selection.removeAll()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            loginStatus = SMAppService.mainApp.status
        }
    }

    // MARK: Sections

    private var header: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 2) {
                Text("每日提醒")
                    .font(.system(size: 17, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                VoiceReminderController.shared.beginListening()
            } label: {
                Label("语音添加", systemImage: "mic")
            }
            .help("也可以在任何地方按 \(VoiceReminderController.shared.hotKeyCombo.label)")
            Button {
                editing = DailyReminder(hour: 23, minute: 0)
            } label: {
                Label("新建", systemImage: "plus")
            }
            .disabled(store.reminders.count >= DailyReminder.maxCount)
            .help(store.reminders.count >= DailyReminder.maxCount
                  ? "最多 \(DailyReminder.maxCount) 条提醒"
                  : "添加提醒")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        guard !store.reminders.isEmpty else { return "还没有提醒" }
        var text = "共 \(store.reminders.count) 条，已开启 \(enabledCount) 条"
        if let upcoming = scheduler.upcoming {
            text += " · 下次：\(Self.relativeLabel(upcoming.date)) \(upcoming.reminder.timeLabel)"
        }
        return text
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("还没有提醒")
                .font(.system(size: 14, weight: .medium))
            Text("可以加睡觉、喝水、拉伸之类的习惯提醒\n每天同一时间准时提醒你。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("添加提醒") {
                editing = DailyReminder(hour: 23, minute: 0)
            }
            .padding(.top, 4)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.reminders.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) { reminder in
                ReminderListRow(reminder: reminder, isOn: enabledBinding(for: reminder.id)) {
                    editing = reminder
                }
                .tag(reminder.id)
            }
        }
        .contextMenu(forSelectionType: UUID.self) { ids in
            // Right-click on empty space passes no ids; don't offer actions that would hit everything
            if ids.isEmpty {
                Button("新建提醒…") { editing = DailyReminder(hour: 23, minute: 0) }
                    .disabled(store.reminders.count >= DailyReminder.maxCount)
            } else {
                selectionMenu(ids)
            }
        } primaryAction: { ids in
            if ids.count == 1, let id = ids.first {
                editing = store.reminders.first { $0.id == id }
            }
        }
    }

    @ViewBuilder
    private func selectionMenu(_ ids: Set<UUID>) -> some View {
        if ids.count == 1, let id = ids.first, let reminder = store.reminders.first(where: { $0.id == id }) {
            Button("编辑…") { editing = reminder }
            Divider()
        }
        Button("开启") { setEnabled(true, for: ids) }
        Button("关闭") { setEnabled(false, for: ids) }
        Divider()
        Button("删除…") {
            selection = ids
            confirmingDelete = true
        }
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if loginStatus != .enabled && enabledCount > 0 {
                loginHint
            }

            HStack(spacing: 8) {
                Text("语音添加快捷键")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ShortcutRecorder(controller: .shared)
                Spacer()
            }

            HStack(spacing: 8) {
                Text(selection.isEmpty ? "未选择：操作将作用于全部提醒" : "已选 \(selection.count) 条")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button("开启") { setEnabled(true, for: targetIDs) }
                Button("关闭") { setEnabled(false, for: targetIDs) }
                Button("删除…", role: .destructive) { confirmingDelete = true }
            }
            .controlSize(.small)
            .disabled(store.reminders.isEmpty)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }

    private var loginHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.circle")
                .foregroundStyle(.orange)
            Text(loginStatus == .requiresApproval
                 ? "请在 系统设置 → 登录项 中允许 Tick，重启后才能收到完整提醒。"
                 : "建议打开开机自启，重启后也能收到完整的弹窗提醒。")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if loginStatus == .requiresApproval {
                Button("打开设置") {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .controlSize(.small)
            } else {
                Button("打开") {
                    try? SMAppService.mainApp.register()
                    loginStatus = SMAppService.mainApp.status
                }
                .controlSize(.small)
            }
        }
    }

    // MARK: Helpers

    private func enabledBinding(for id: UUID) -> Binding<Bool> {
        Binding(
            get: { store.reminders.first { $0.id == id }?.isEnabled ?? false },
            set: { setEnabled($0, for: [id]) }
        )
    }

    private func setEnabled(_ enabled: Bool, for ids: Set<UUID>) {
        store.reminders = store.reminders.map { r in
            guard ids.contains(r.id) else { return r }
            var r = r
            // A reminder with no days can't fire; leave it off until edited
            r.isEnabled = enabled && !r.weekdays.isEmpty
            return r
        }
    }

    static func relativeLabel(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "今天" }
        if calendar.isDateInTomorrow(date) { return "明天" }
        return calendar.shortWeekdaySymbols[calendar.component(.weekday, from: date) - 1]
    }
}

// MARK: - List Row

private struct ReminderListRow: View {
    let reminder: DailyReminder
    @Binding var isOn: Bool
    let onEdit: () -> Void

    private var nextLabel: String? {
        reminder.nextFireDate(after: Date()).map { ReminderManagerView.relativeLabel($0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(reminder.timeLabel)
                        .font(.system(size: 20, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                    Text(reminder.daysSummary())
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                Text(reminder.note.isEmpty ? "无备注" : reminder.note)
                    .font(.system(size: 12))
                    .foregroundStyle(reminder.note.isEmpty ? .tertiary : .secondary)
                    .lineLimit(1)
            }

            Spacer()

            if reminder.isEnabled, let nextLabel {
                Text(nextLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            Button {
                onEdit()
            } label: {
                Image(systemName: "pencil")
            }
            .buttonStyle(.borderless)
            .help("编辑")
        }
        .padding(.vertical, 4)
        .opacity(reminder.isEnabled ? 1 : 0.55)
    }
}

// MARK: - Edit Sheet

private struct ReminderEditSheet: View {
    let isNew: Bool
    let onSave: (DailyReminder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DailyReminder

    init(reminder: DailyReminder, isNew: Bool, onSave: @escaping (DailyReminder) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        _draft = State(initialValue: reminder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(isNew ? "新建提醒" : "编辑提醒")
                .font(.headline)

            ReminderForm(draft: $draft)

            HStack {
                Spacer()
                Button("取消") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("保存") {
                    onSave(draft)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(draft.weekdays.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
    }
}

// MARK: - Shortcut Recorder

/// Click, then press a new combination (Esc cancels)
private struct ShortcutRecorder: View {
    @ObservedObject var controller: VoiceReminderController
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        HStack(spacing: 8) {
            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? "请按下新的快捷键…" : controller.hotKeyCombo.label)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(minWidth: 90)
            }
            .controlSize(.small)
            .help("点击后按下新的组合键，需包含 ⌃ 或 ⌥；按 Esc 取消")

            if isRecording {
                Button("恢复默认") {
                    apply(.defaultVoiceReminder)
                }
                .controlSize(.small)
            }

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
            }
        }
        .onDisappear { stopRecording() }
    }

    private func startRecording() {
        message = nil
        isRecording = true
        controller.suspendHotKey()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if event.keyCode == 53 { // Esc
                stopRecording()
                return nil
            }
            if let combo = HotKeyCombo(event: event) {
                apply(combo)
            } else {
                message = "需要同时按住 ⌃ 或 ⌥"
            }
            return nil
        }
    }

    private func apply(_ combo: HotKeyCombo) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        message = controller.setHotKey(combo) ? nil : "\(combo.label) 无法使用（可能被系统保留），换一个吧"
    }

    private func stopRecording() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if isRecording {
            isRecording = false
            controller.resumeHotKey()
        }
    }
}

// MARK: - Reminder Form

/// Time, note and repeat days; shared by the edit sheet and the voice confirm card
struct ReminderForm: View {
    @Binding var draft: DailyReminder

    private var calendar: Calendar { .current }

    private var time: Binding<Date> {
        Binding(
            get: {
                // Fixed reference day: on a DST spring-forward day some times don't exist
                calendar.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                   hour: draft.hour, minute: draft.minute)) ?? Date()
            },
            set: { newValue in
                let parts = calendar.dateComponents([.hour, .minute], from: newValue)
                draft.hour = parts.hour ?? draft.hour
                draft.minute = parts.minute ?? draft.minute
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                TextField("备注，比如：该睡觉了", text: $draft.note)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(DailyReminder.orderedWeekdays(calendar: calendar), id: \.self) { weekday in
                        dayChip(weekday)
                    }
                }
                HStack(spacing: 6) {
                    quickDays("每天", DailyReminder.everyDay)
                    quickDays("工作日", DailyReminder.weekdaysOnly)
                    quickDays("周末", DailyReminder.weekendsOnly)
                    if draft.weekdays.isEmpty {
                        Text("至少选择一天")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }
        }
    }

    private func dayChip(_ weekday: Int) -> some View {
        let isOn = draft.weekdays.contains(weekday)
        return Button {
            if isOn {
                draft.weekdays.remove(weekday)
            } else {
                draft.weekdays.insert(weekday)
            }
        } label: {
            Text(calendar.veryShortWeekdaySymbols[weekday - 1])
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isOn ? .white : .secondary)
                .frame(width: 26, height: 26)
                .background(Circle().fill(isOn ? Color.accentColor : Color.secondary.opacity(0.12)))
        }
        .buttonStyle(.plain)
    }

    private func quickDays(_ label: String, _ days: Set<Int>) -> some View {
        Button(label) { draft.weekdays = days }
            .controlSize(.small)
            .buttonStyle(.bordered)
            .tint(draft.weekdays == days ? .accentColor : nil)
    }
}
