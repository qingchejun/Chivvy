import AppKit
import ServiceManagement
import SwiftUI

// MARK: - Reminders Pane

struct RemindersPane: View {
    @ObservedObject var store: ReminderStore
    @ObservedObject var scheduler: ReminderScheduler
    @ObservedObject private var voice = VoiceReminderController.shared

    @State private var selection = Set<UUID>()
    @State private var editing: DailyReminder?
    @State private var confirmingDelete = false

    private var enabledCount: Int { store.reminders.filter(\.isEnabled).count }
    private var isFull: Bool { store.reminders.count >= DailyReminder.maxCount }

    /// Batch actions apply to the selection, or to everything when nothing is selected
    private var targetIDs: Set<UUID> {
        selection.isEmpty ? Set(store.reminders.map(\.id)) : selection
    }

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: MainSection.reminders.title) {
                Button {
                    voice.beginListening()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "mic")
                        Text(L("语音添加", "Add by Voice"))
                        Keycap(text: voice.hotKeyCombo.label)
                    }
                }
                .buttonStyle(.chivvy(.secondary, size: .regular))
                .fixedSize()
                .help(L("也可以在任何地方按 \(voice.hotKeyCombo.label)", "Or press \(voice.hotKeyCombo.label) anywhere"))

                Button {
                    editing = DailyReminder(hour: 23, minute: 0)
                } label: {
                    Label(L("新建", "New"), systemImage: "plus")
                }
                .buttonStyle(.chivvy(.primary, size: .regular))
                .fixedSize()
                .disabled(isFull)
                .help(isFull ? L("最多 \(DailyReminder.maxCount) 条提醒", "Up to \(DailyReminder.maxCount) reminders")
                             : L("添加提醒", "Add Reminder"))
            }

            VStack(alignment: .leading, spacing: Theme.Space.m) {
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)

                LoginHint(hasActiveReminders: enabledCount > 0)

                if store.reminders.isEmpty {
                    emptyState
                } else {
                    list
                    footer
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.bottom, Theme.Space.l)
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .sheet(item: $editing) { reminder in
            let isNew = !store.reminders.contains { $0.id == reminder.id }
            ReminderEditSheet(reminder: reminder, isNew: isNew) { saved in
                if let index = store.reminders.firstIndex(where: { $0.id == saved.id }) {
                    store.reminders[index] = saved
                } else {
                    store.reminders.append(saved)
                }
            } onDelete: { deleted in
                store.reminders.removeAll { $0.id == deleted.id }
                selection.remove(deleted.id)
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
    }

    // MARK: Sections

    private var subtitle: String {
        guard !store.reminders.isEmpty else {
            return L("最多 \(DailyReminder.maxCount) 个", "Up to \(DailyReminder.maxCount)")
        }
        return L("\(store.reminders.count) 个提醒，\(enabledCount) 个开启 · 最多 \(DailyReminder.maxCount) 个",
                 "\(store.reminders.count) reminders, \(enabledCount) on · up to \(DailyReminder.maxCount)")
    }

    private var emptyState: some View {
        VStack(spacing: Theme.Space.s) {
            Image(systemName: "bell.badge")
                .font(.system(size: 30, weight: .light))
                .foregroundStyle(Theme.brandText)
                .frame(width: 64, height: 64)
                .background(Theme.brandSoft, in: Circle())
                .padding(.bottom, Theme.Space.xs)
            Text(L("还没有提醒", "No reminders yet"))
                .font(Theme.Font.headline)
            Text(L("加上睡觉、喝水、拉伸之类的习惯，\n每天同一时间准时提醒你。",
                   "Add habits like bedtime, water or stretching.\nChivvy pops up at the same time every day."))
                .font(Theme.Font.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button(L("添加提醒", "Add Reminder")) {
                editing = DailyReminder(hour: 23, minute: 0)
            }
            .buttonStyle(.chivvy(.primary))
            .padding(.top, Theme.Space.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        List(selection: $selection) {
            ForEach(store.reminders.sorted { ($0.hour, $0.minute) < ($1.hour, $1.minute) }) { reminder in
                ReminderListRow(reminder: reminder,
                                isNext: scheduler.upcoming?.reminder.id == reminder.id,
                                isOn: enabledBinding(for: reminder.id))
                    .tag(reminder.id)
            }
        }
        .listStyle(.inset(alternatesRowBackgrounds: false))
        .scrollContentBackground(.hidden)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.card))
        .overlay(RoundedRectangle(cornerRadius: Theme.Radius.card).strokeBorder(Theme.separator.opacity(0.6)))
        .contextMenu(forSelectionType: UUID.self) { ids in
            // Right-click on empty space passes no ids; don't offer actions that would hit everything
            if ids.isEmpty {
                Button(L("新建提醒…", "New Reminder…")) { editing = DailyReminder(hour: 23, minute: 0) }
                    .disabled(isFull)
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
        HStack(spacing: Theme.Space.xs) {
            Text(selection.isEmpty
                 ? L("双击编辑 · 右键更多操作", "Double-click to edit · right-click for more")
                 : L("已选 \(selection.count) 个", "\(selection.count) selected"))
                .font(Theme.Font.caption)
                .foregroundStyle(.tertiary)
            Spacer()
            Button(selection.isEmpty ? L("全部开启", "All On") : L("开启", "Turn On")) { setEnabled(true, for: targetIDs) }
                .buttonStyle(.chivvy(.text, size: .small))
            Button(selection.isEmpty ? L("全部关闭", "All Off") : L("关闭", "Turn Off")) { setEnabled(false, for: targetIDs) }
                .buttonStyle(.chivvy(.text, size: .small))
            Button(selection.isEmpty ? L("清空…", "Clear…") : L("删除…", "Delete…")) { confirmingDelete = true }
                .buttonStyle(.chivvy(.danger, size: .small))
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
}

// MARK: - List Row

private struct ReminderListRow: View {
    let reminder: DailyReminder
    let isNext: Bool
    @Binding var isOn: Bool

    private var nextLabel: String? {
        guard reminder.isEnabled else { return L("已关闭", "Off") }
        return reminder.nextFireDate(after: Date()).map { DailyReminder.relativeDayLabel($0) }
    }

    var body: some View {
        HStack(spacing: 14) {
            HStack(spacing: 14) {
                Text(reminder.timeLabel)
                    .font(.system(size: 22, weight: .semibold).monospacedDigit())
                    .tracking(-0.3)
                    .frame(width: 70, alignment: .leading)

                VStack(alignment: .leading, spacing: 2) {
                    Text(reminder.note.isEmpty ? L("无备注", "No note") : reminder.note)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(reminder.note.isEmpty ? .secondary : .primary)
                        .lineLimit(1)
                    Text(reminder.daysSummary())
                        .font(Theme.Font.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: Theme.Space.s)

                if let nextLabel {
                    Text(nextLabel)
                        .font(Theme.Font.caption)
                        .foregroundStyle(isNext ? Theme.brandText : Color.secondary)
                }
            }
            .opacity(reminder.isEnabled ? 1 : 0.45)

            Toggle("\(reminder.timeLabel) \(reminder.note)", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.brandSwitch)
                .help(reminder.isEnabled ? L("关闭这条提醒", "Turn off") : L("开启这条提醒", "Turn on"))
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 4)
    }
}

// MARK: - Edit Sheet

private struct ReminderEditSheet: View {
    let isNew: Bool
    let onSave: (DailyReminder) -> Void
    let onDelete: (DailyReminder) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var draft: DailyReminder

    init(reminder: DailyReminder, isNew: Bool,
         onSave: @escaping (DailyReminder) -> Void, onDelete: @escaping (DailyReminder) -> Void) {
        self.isNew = isNew
        self.onSave = onSave
        self.onDelete = onDelete
        _draft = State(initialValue: reminder)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Space.l) {
            Text(isNew ? L("新建提醒", "New Reminder") : L("编辑提醒", "Edit Reminder"))
                .font(Theme.Font.headline)

            ReminderForm(draft: $draft)

            HStack(spacing: Theme.Space.s) {
                if !isNew {
                    Button(L("删除", "Delete")) {
                        onDelete(draft)
                        dismiss()
                    }
                    .buttonStyle(.chivvy(.danger))
                }
                Spacer()
                Button(L("取消", "Cancel")) { dismiss() }
                    .buttonStyle(.chivvy(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button(L("保存", "Save")) {
                    onSave(draft)
                    dismiss()
                }
                .buttonStyle(.chivvy(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(draft.weekdays.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 380)
        .tint(Theme.brand)
    }
}

// MARK: - Login Hint

/// Without auto-start, reminders only arrive as plain notifications after a restart
struct LoginHint: View {
    let hasActiveReminders: Bool
    @State private var status = SMAppService.mainApp.status

    private var visible: Bool {
        status == .requiresApproval || (status != .enabled && hasActiveReminders)
    }

    var body: some View {
        Group {
            if visible {
                HStack(spacing: Theme.Space.s) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(Theme.brandText)
                    Text(status == .requiresApproval
                         ? L("需要在 系统设置 → 登录项 中允许 Chivvy", "Allow Chivvy in System Settings → Login Items")
                         : L("建议打开开机自启，重启后也能收到弹窗提醒", "Turn on auto-start so alerts survive a restart"))
                        .font(.system(size: 12))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: Theme.Space.s)
                    Button(status == .requiresApproval ? L("打开设置", "Open Settings") : L("打开", "Turn On")) {
                        if status == .requiresApproval {
                            SMAppService.openSystemSettingsLoginItems()
                        } else {
                            try? SMAppService.mainApp.register()
                            status = SMAppService.mainApp.status
                            NotificationCenter.default.post(name: .loginItemChanged, object: nil)
                        }
                    }
                    .buttonStyle(.chivvy(.text, size: .small))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, Theme.Space.s)
                .background(Theme.brandSoft, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            status = SMAppService.mainApp.status
        }
        .onReceive(NotificationCenter.default.publisher(for: .loginItemChanged)) { _ in
            status = SMAppService.mainApp.status
        }
    }
}

extension Notification.Name {
    /// Posted after Chivvy registers or unregisters itself as a login item
    static let loginItemChanged = Notification.Name("ChivvyLoginItemChanged")
}

// MARK: - Shortcut Recorder

/// Click, then press a new combination (Esc cancels)
struct ShortcutRecorder: View {
    @ObservedObject var controller: VoiceReminderController
    @State private var isRecording = false
    @State private var monitor: Any?
    @State private var message: String?

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            if let message {
                Text(message)
                    .font(Theme.Font.caption)
                    .foregroundStyle(Theme.brandText)
                    .lineLimit(2)
            }

            Button {
                isRecording ? stopRecording() : startRecording()
            } label: {
                Text(isRecording ? L("请按下新的快捷键…", "Press a shortcut…") : controller.hotKeyCombo.label)
                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                    .foregroundStyle(isRecording ? Theme.brandText : Color.primary)
                    .frame(minWidth: 72)
                    .padding(.horizontal, 10)
                    .frame(height: 24)
                    .background(Theme.content, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control)
                            .strokeBorder(isRecording ? Theme.brand : Theme.separator, lineWidth: 1)
                    )
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(L("点击后按下新的组合键，需包含 ⌃ 或 ⌥；按 Esc 取消", "Click, then press a new combination with ⌃ or ⌥. Esc cancels."))

            Button(L("恢复默认", "Restore Default")) {
                apply(.defaultVoiceReminder)
            }
            .buttonStyle(.chivvy(.text, size: .small))
            .disabled(controller.hotKeyCombo == .defaultVoiceReminder && !isRecording)
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
        VStack(alignment: .leading, spacing: Theme.Space.m) {
            HStack(spacing: Theme.Space.s) {
                DatePicker("", selection: time, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                TextField(L("备注，比如：该睡觉了", "Note, e.g. Time for bed"), text: $draft.note)
                    .textFieldStyle(.roundedBorder)
            }

            HStack(spacing: 6) {
                ForEach(DailyReminder.orderedWeekdays(calendar: calendar), id: \.self) { weekday in
                    dayChip(weekday)
                }
            }

            HStack(spacing: Theme.Space.xs) {
                quickDays(L("每天", "Every day"), DailyReminder.everyDay)
                quickDays(L("工作日", "Weekdays"), DailyReminder.weekdaysOnly)
                quickDays(L("周末", "Weekends"), DailyReminder.weekendsOnly)
                if draft.weekdays.isEmpty {
                    Text(L("至少选择一天", "Pick at least one day"))
                        .font(Theme.Font.caption)
                        .foregroundStyle(Theme.brandText)
                        .padding(.leading, Theme.Space.xs)
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
                .font(.system(size: 12, weight: isOn ? .semibold : .regular))
                .foregroundStyle(isOn ? Theme.onBrand : Color.secondary)
                .frame(width: 28, height: 28)
                .background(isOn ? Theme.brand : Theme.fill, in: Circle())
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }

    private func quickDays(_ label: String, _ days: Set<Int>) -> some View {
        let isOn = draft.weekdays == days
        return Button {
            draft.weekdays = days
        } label: {
            Text(label)
                .font(.system(size: 12, weight: isOn ? .semibold : .medium))
                .foregroundStyle(isOn ? Theme.brandText : Color.secondary)
                .padding(.horizontal, Theme.Space.s)
                .frame(height: 22)
                .background(isOn ? Theme.brandSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
