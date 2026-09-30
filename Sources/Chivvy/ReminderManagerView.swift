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
            window.title = Self.title
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(
                rootView: LanguageRoot { ReminderManagerView(store: .shared, scheduler: .shared) }
            )
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static var title: String { L("提醒", "Reminders") }

    func languageDidChange() {
        window?.title = Self.title
    }
}

extension NSWindow {
    /// The Reminders window is a secondary window; code looking for "the" Chivvy window skips it
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
                ? L("删除全部 \(targetIDs.count) 条提醒？", targetIDs.count == 1 ? "Delete 1 reminder?" : "Delete all \(targetIDs.count) reminders?")
                : L("删除 \(targetIDs.count) 条提醒？", targetIDs.count == 1 ? "Delete 1 reminder?" : "Delete \(targetIDs.count) reminders?"),
            isPresented: $confirmingDelete,
            titleVisibility: .visible
        ) {
            Button(L("删除", "Delete"), role: .destructive) {
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
                Text(L("每日弹窗提醒", "Daily pop-up reminders"))
                    .font(.system(size: 17, weight: .semibold))
                Text(headerSubtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button {
                VoiceReminderController.shared.beginListening()
            } label: {
                Label(L("语音添加", "Add by Voice"), systemImage: "mic")
            }
            .help(L("也可以在任何地方按 \(VoiceReminderController.shared.hotKeyCombo.label)",
                     "Or press \(VoiceReminderController.shared.hotKeyCombo.label) anywhere"))
            Button {
                editing = DailyReminder(hour: 23, minute: 0)
            } label: {
                Label(L("新建", "New"), systemImage: "plus")
            }
            .disabled(store.reminders.count >= DailyReminder.maxCount)
            .help(store.reminders.count >= DailyReminder.maxCount
                  ? L("最多 \(DailyReminder.maxCount) 条提醒", "Up to \(DailyReminder.maxCount) reminders")
                  : L("添加提醒", "Add Reminder"))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var headerSubtitle: String {
        guard !store.reminders.isEmpty else { return L("还没有提醒", "No reminders yet") }
        var text = L("共 \(store.reminders.count) 条，已开启 \(enabledCount) 条",
                     "\(store.reminders.count) total, \(enabledCount) on")
        if let upcoming = scheduler.upcoming {
            text += L(" · 下次：", " · Next: ") + "\(Self.relativeLabel(upcoming.date)) \(upcoming.reminder.timeLabel)"
        }
        return text
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "moon.zzz")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text(L("还没有提醒", "No reminders yet"))
                .font(.system(size: 14, weight: .medium))
            Text(L("可以加睡觉、喝水、拉伸之类的习惯提醒\n每天同一时间准时提醒你。", "Add habits like bedtime, water or stretching.\nChivvy reminds you at the same time every day."))
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("添加提醒", "Add Reminder")) {
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
                Button(L("新建提醒…", "New Reminder…")) { editing = DailyReminder(hour: 23, minute: 0) }
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
            Button(L("编辑…", "Edit…")) { editing = reminder }
            Divider()
        }
        Button(L("开启", "Turn On")) { setEnabled(true, for: ids) }
        Button(L("关闭", "Turn Off")) { setEnabled(false, for: ids) }
        Divider()
        Button(L("删除…", "Delete…")) {
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
                Text(L("语音添加快捷键", "Voice shortcut"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                ShortcutRecorder(controller: .shared)
                Spacer()
            }

            HStack(spacing: 8) {
                Text(selection.isEmpty
                     ? L("未选择：操作将作用于全部提醒", "No selection: applies to all")
                     : L("已选 \(selection.count) 条", "\(selection.count) selected"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                Spacer()
                Button(L("开启", "Turn On")) { setEnabled(true, for: targetIDs) }
                Button(L("关闭", "Turn Off")) { setEnabled(false, for: targetIDs) }
                Button(L("删除…", "Delete…"), role: .destructive) { confirmingDelete = true }
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
                 ? L("请在 系统设置 → 登录项 中允许 Chivvy，重启后才能收到完整提醒。", "Allow Chivvy in System Settings → Login Items to keep full alerts after a restart.")
                 : L("建议打开开机自启，重启后也能收到完整的弹窗提醒。", "Turn on auto-start so full alerts keep working after a restart."))
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            Spacer()
            if loginStatus == .requiresApproval {
                Button(L("打开设置", "Open Settings")) {
                    SMAppService.openSystemSettingsLoginItems()
                }
                .controlSize(.small)
            } else {
                Button(L("打开", "Turn On")) {
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
        if calendar.isDateInToday(date) { return L("今天", "Today") }
        if calendar.isDateInTomorrow(date) { return L("明天", "Tomorrow") }
        return DailyReminder.shortName(weekday: calendar.component(.weekday, from: date))
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
                Text(reminder.note.isEmpty ? L("无备注", "No note") : reminder.note)
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
            .help(L("编辑", "Edit"))
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
            Text(isNew ? L("新建提醒", "New Reminder") : L("编辑提醒", "Edit Reminder"))
                .font(.headline)

            ReminderForm(draft: $draft)

            HStack {
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(L("保存", "Save")) {
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
                Text(isRecording ? L("请按下新的快捷键…", "Press a shortcut…") : controller.hotKeyCombo.label)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .frame(minWidth: 90)
            }
            .controlSize(.small)
            .help(L("点击后按下新的组合键，需包含 ⌃ 或 ⌥；按 Esc 取消", "Click, then press a new combination with ⌃ or ⌥. Esc cancels."))

            if isRecording {
                Button(L("恢复默认", "Restore Defaults")) {
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
                message = L("需要同时按住 ⌃ 或 ⌥", "Hold ⌃ or ⌥ too")
            }
            return nil
        }
    }

    private func apply(_ combo: HotKeyCombo) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        isRecording = false
        message = controller.setHotKey(combo) ? nil : L("\(combo.label) 无法使用（可能被系统保留），换一个吧",
                                                               "\(combo.label) isn't available (may be reserved by the system). Try another.")
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
                TextField(L("备注，比如：该睡觉了", "Note, e.g. Time for bed"), text: $draft.note)
                    .textFieldStyle(.roundedBorder)
            }

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    ForEach(DailyReminder.orderedWeekdays(calendar: calendar), id: \.self) { weekday in
                        dayChip(weekday)
                    }
                }
                HStack(spacing: 6) {
                    quickDays(L("每天", "Every day"), DailyReminder.everyDay)
                    quickDays(L("工作日", "Weekdays"), DailyReminder.weekdaysOnly)
                    quickDays(L("周末", "Weekends"), DailyReminder.weekendsOnly)
                    if draft.weekdays.isEmpty {
                        Text(L("至少选择一天", "Pick at least one day"))
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
            Text(DailyReminder.letter(weekday: weekday))
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
