import AppKit
import Combine
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private let hasShownBackgroundTipKey = "hasShownBackgroundTip"
    private var tipPopover: NSPopover?
    private var languageObserver: AnyCancellable?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Settle the language before anything writes the keys the upgrade check looks at
        _ = L10n.current
        menuBarManager = MenuBarManager(timerManager: TimerManager.shared)
        NotificationManager.shared.requestPermission()
        ReminderScheduler.shared.start()
        VoiceReminderController.shared.start()

        // Open windows rebuild themselves (LanguageRoot); these parts live outside SwiftUI
        languageObserver = LanguageStore.shared.$language
            .dropFirst()
            .sink { _ in
                // L10n.current is already saved when this fires, so L(...) returns the new language
                ReminderScheduler.shared.languageDidChange()
            }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(windowWillClose),
            name: NSWindow.willCloseNotification,
            object: nil
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return false
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // A floating alert or voice panel also counts as "visible"; check the main window itself
        Task { @MainActor in
            if MainWindowRouter.shared.window?.isVisible != true {
                MainWindowRouter.shared.open()
            }
        }
        return true
    }

    @MainActor @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              MainWindowRouter.shared.isMainWindow(window) else { return }
        MainWindowRouter.shared.detach(window)
        guard !UserDefaults.standard.bool(forKey: hasShownBackgroundTipKey) else {
            return
        }

        UserDefaults.standard.set(true, forKey: hasShownBackgroundTipKey)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.showMenuBarTip()
        }
    }

    @MainActor private func showMenuBarTip() {
        guard let button = menuBarManager?.statusButton else { return }

        let popover = NSPopover()
        popover.behavior = .transient
        popover.contentViewController = NSHostingController(
            rootView: LanguageRoot { BackgroundTipView() }
        )
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        self.tipPopover = popover

        DispatchQueue.main.asyncAfter(deadline: .now() + 4) { [weak self] in
            self?.tipPopover?.performClose(nil)
            self?.tipPopover = nil
        }
    }
}

struct BackgroundTipView: View {
    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(Theme.brand)

            VStack(alignment: .leading, spacing: 2) {
                Text(L("Chivvy 还在这里运行", "Chivvy is still running"))
                    .font(.system(size: 13, weight: .semibold))
                Text(L("点击菜单栏图标即可打开", "Click this icon to open it"))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, Theme.Space.l)
        .padding(.vertical, Theme.Space.m)
    }
}
