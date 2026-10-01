import AppKit
import ServiceManagement
import SwiftUI

struct SettingsPane: View {
    @ObservedObject private var presetStore = PresetStore.shared
    @ObservedObject private var languages = LanguageStore.shared
    @ObservedObject private var reminders = ReminderStore.shared
    @AppStorage(MainWindowRouter.alwaysOnTopKey) private var alwaysOnTop = false

    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var showPresetEditor = false

    var body: some View {
        VStack(spacing: 0) {
            PaneHeader(title: MainSection.settings.title)

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    general
                    voice
                    presets
                    about
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.bottom, 20)
            }
        }
        .sheet(isPresented: $showPresetEditor) {
            PresetEditorView(store: presetStore)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
        .onReceive(NotificationCenter.default.publisher(for: .loginItemChanged)) { _ in
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    // MARK: Sections

    private var general: some View {
        FormSection(title: L("通用", "General")) {
            FormRow(label: L("开机自启", "Launch at login"), divider: false) {
                Toggle(L("开机自启", "Launch at login"), isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                    .labelsHidden()
                    .toggleStyle(.brandSwitch)
            }
            LoginHint(hasActiveReminders: reminders.reminders.contains(where: \.isEnabled))
                .padding(.horizontal, 10)
                .padding(.bottom, launchAtLogin ? 0 : Theme.Space.s)
            FormRow(label: L("窗口置顶", "Keep window on top")) {
                Toggle(L("窗口置顶", "Keep window on top"), isOn: Binding(get: { alwaysOnTop }, set: { newValue in
                    alwaysOnTop = newValue
                    MainWindowRouter.shared.applyPin()
                }))
                .labelsHidden()
                .toggleStyle(.brandSwitch)
            }
            FormRow(label: L("界面语言", "Language")) {
                SegmentedChips(
                    items: AppLanguage.allCases,
                    selection: languages.language,
                    label: { $0 == .zh ? "中文" : "English" },
                    onSelect: { languages.set($0) },
                    height: 22
                )
            }
        }
    }

    private var voice: some View {
        FormSection(
            title: L("语音添加", "Add by voice"),
            footer: L("按下快捷键后说：“十分钟后提醒我关火”或“工作日早上八点半提醒我喝水”。",
                      "Press the shortcut and speak Mandarin, e.g. “十分钟后提醒我关火” or “工作日早上八点半提醒我喝水”.")
        ) {
            FormRow(label: L("快捷键", "Shortcut"), divider: false) {
                ShortcutRecorder(controller: .shared)
            }
        }
    }

    private var presets: some View {
        FormSection(title: L("倒计时预设", "Countdown presets")) {
            HStack(spacing: 6) {
                ForEach(presetStore.presets) { preset in
                    Text(preset.displayLabel)
                        .font(.system(size: 12))
                        .padding(.horizontal, Theme.Space.s)
                        .padding(.vertical, 2)
                        .background(Theme.fill, in: RoundedRectangle(cornerRadius: 5))
                }
                Spacer(minLength: Theme.Space.s)
                Button(L("编辑…", "Edit…")) { showPresetEditor = true }
                    .buttonStyle(.chivvy(.secondary, size: .small))
            }
            .padding(.horizontal, Theme.Space.m)
            .frame(minHeight: 38)
        }
    }

    private var about: some View {
        HStack(spacing: 10) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 28, height: 28)
            VStack(alignment: .leading, spacing: 1) {
                Text("Chivvy \(Self.version)")
                    .font(.system(size: 12, weight: .semibold))
                Text(L("个人与非商业使用免费 · PolyForm Noncommercial", "Free for personal & noncommercial use · PolyForm Noncommercial"))
                    .font(Theme.Font.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Link("GitHub", destination: URL(string: "https://github.com/qingchejun/Chivvy")!)
                .font(Theme.Font.caption)
                .foregroundStyle(Theme.brandText)
        }
        .padding(.top, Theme.Space.xs)
    }

    // MARK: Helpers

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    private func setLaunchAtLogin(_ on: Bool) {
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Leave the switch showing the real state
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
        NotificationCenter.default.post(name: .loginItemChanged, object: nil)
    }
}
