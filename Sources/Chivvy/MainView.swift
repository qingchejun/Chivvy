import AppKit
import SwiftUI

// MARK: - Router

/// Owns "the" main window so the menu bar, the voice panel and the Dock can bring it up on a given section
@MainActor
final class MainWindowRouter: ObservableObject {
    static let shared = MainWindowRouter()

    @Published var section = MainSection.saved() {
        didSet { section.save() }
    }

    private(set) weak var window: NSWindow?
    /// SwiftUI's openWindow, captured from the view; used when the window has been released
    var reopen: (() -> Void)?

    static let alwaysOnTopKey = "alwaysOnTop"

    private init() {}

    func attach(_ window: NSWindow) {
        guard self.window !== window else { return }
        self.window = window
        applyPin()
    }

    func isMainWindow(_ window: NSWindow) -> Bool { window === self.window }

    func open(_ section: MainSection? = nil) {
        // Switching sections would tear down a pane under its open sheet (and its unsaved edits)
        if let section, window?.attachedSheet == nil { self.section = section }
        NSApp.activate(ignoringOtherApps: true)
        // openWindow brings the existing window forward or recreates a closed one
        if let reopen {
            reopen()
        } else {
            window?.makeKeyAndOrderFront(nil)
        }
    }

    func detach(_ window: NSWindow) {
        if window === self.window { self.window = nil }
    }

    func applyPin() {
        window?.level = UserDefaults.standard.bool(forKey: Self.alwaysOnTopKey) ? .floating : .normal
    }
}

// MARK: - Main View

struct MainView: View {
    @ObservedObject private var router = MainWindowRouter.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(router: router)
                .frame(width: 184)
            Rectangle()
                .fill(Theme.separator)
                .frame(width: 1)
            Group {
                switch router.section {
                case .timer: TimerPane()
                case .reminders: RemindersPane(store: .shared, scheduler: .shared)
                case .settings: SettingsPane()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Theme.content)
        }
        .ignoresSafeArea(.container, edges: .top)
        .frame(minWidth: 640, idealWidth: 640, minHeight: 460, idealHeight: 460)
        .tint(Theme.brand)
        .background(WindowAccessor { router.attach($0) })
        .onAppear {
            let openWindow = openWindow
            router.reopen = { openWindow(id: "main") }
        }
    }
}

/// Title row at the top of each pane; the window has no title bar of its own
struct PaneHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            Text(title)
                .font(Theme.Font.headline)
            Spacer()
            trailing()
        }
        .padding(.leading, Theme.Space.xl)
        .padding(.trailing, Theme.Space.l)
        .frame(height: 52)
    }
}

extension PaneHeader where Trailing == EmptyView {
    init(title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Sidebar

private struct Sidebar: View {
    @ObservedObject var router: MainWindowRouter
    @ObservedObject private var reminders = ReminderStore.shared
    @ObservedObject private var scheduler = ReminderScheduler.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            // Room for the traffic lights
            Spacer().frame(height: 44)

            ForEach(MainSection.allCases, id: \.self) { section in
                item(section)
            }

            Spacer()

            if let upcoming = scheduler.upcoming {
                Button {
                    router.section = .reminders
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(L("下一次提醒", "Next reminder"))
                            .font(Theme.Font.caption)
                            .foregroundStyle(.secondary)
                        Text(nextLine(upcoming))
                            .font(.system(size: 13, weight: .semibold).monospacedDigit())
                            .lineLimit(1)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(Theme.fill, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 10)
        .padding(.bottom, Theme.Space.m)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(VisualEffectBackground(material: .sidebar).ignoresSafeArea())
    }

    private func nextLine(_ upcoming: ScheduledReminder) -> String {
        let r = upcoming.reminder
        let day = DailyReminder.relativeDayLabel(upcoming.date)
        let when = day == L("今天", "Today") ? r.timeLabel : "\(day) \(r.timeLabel)"
        return r.note.isEmpty ? when : "\(when) · \(r.note)"
    }

    private func item(_ section: MainSection) -> some View {
        let isOn = router.section == section
        return Button {
            router.section = section
        } label: {
            HStack(spacing: Theme.Space.s) {
                Image(systemName: section.symbol)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(isOn ? Theme.brandText : Color.secondary)
                    .frame(width: 18)
                Text(section.title)
                    .font(.system(size: 13, weight: isOn ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
                if section == .reminders, !reminders.reminders.isEmpty {
                    Text("\(reminders.reminders.count)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Space.s)
            .frame(height: 30)
            .background(isOn ? Theme.brandSoft : .clear, in: RoundedRectangle(cornerRadius: Theme.Radius.control))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Window Access

/// Hands the hosting NSWindow to SwiftUI code that needs AppKit (window level, bringing it forward)
struct WindowAccessor: NSViewRepresentable {
    let onWindow: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { [weak view] in
            if let window = view?.window { onWindow(window) }
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { [weak nsView] in
            if let window = nsView?.window { onWindow(window) }
        }
    }
}
