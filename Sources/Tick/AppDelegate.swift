import AppKit
import ServiceManagement
import SwiftUI

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuBarManager: MenuBarManager?
    private let hasShownBackgroundTipKey = "hasShownBackgroundTip"
    private var tipPopover: NSPopover?

    func applicationDidFinishLaunching(_ notification: Notification) {
        menuBarManager = MenuBarManager(timerManager: TimerManager.shared)
        NotificationManager.shared.requestPermission()
        ReminderScheduler.shared.start()

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
        // Check the main window itself: an open Reminders window also counts as "visible"
        for window in NSApp.windows where window.canBecomeKey && !window.isReminderWindow {
            if !window.isVisible {
                window.makeKeyAndOrderFront(nil)
            }
            return true
        }
        return true
    }

    @objc private func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window.canBecomeKey,
              !window.isReminderWindow,
              !UserDefaults.standard.bool(forKey: hasShownBackgroundTipKey) else {
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
            rootView: BackgroundTipView()
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
            Image(systemName: "info.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(.accentColor)

            Text("Tick 仍在这里运行。\n点击这个图标即可打开。")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .lineSpacing(2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
