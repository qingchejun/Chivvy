import AppKit
import SwiftUI

struct AlertAction {
    let label: String
    let handler: () -> Void
}

@MainActor
final class AlertPanel {
    private var panel: NSPanel?
    /// Panels on screen across all instances, used to cascade overlapping alerts
    private static var visibleCount = 0
    private static let width: CGFloat = 320

    /// `snoozeActions` show as grey buttons under "知道了"; each also dismisses the panel.
    func show(_ text: AlertText, snoozeActions: [AlertAction] = []) {
        close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: 0),
            styleMask: [.nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .screenSaver
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        // Show on whichever Space is active, including over full-screen apps
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let dismiss: () -> Void = { [weak self] in
            self?.close()
        }
        let actions = snoozeActions.map { action in
            AlertAction(label: action.label) { dismiss(); action.handler() }
        }
        let content = LanguageRoot {
            AlertContentView(text: text, snoozeActions: actions, onDismiss: dismiss)
        }

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: Self.width, height: 1)
        hostingView.setFrameSize(hostingView.fittingSize)
        panel.setContentSize(hostingView.fittingSize)
        panel.contentView = hostingView

        panel.center()
        if Self.visibleCount > 0 {
            // Another alert (timer vs. reminder) is already centered; don't hide behind it
            let offset = CGFloat(Self.visibleCount) * 28
            panel.setFrameOrigin(NSPoint(x: panel.frame.minX + offset, y: panel.frame.minY - offset))
        }
        panel.makeKeyAndOrderFront(nil)

        self.panel = panel
        Self.visibleCount += 1
        NotificationManager.shared.startAlertSound(for: self)
    }

    func close() {
        guard let panel else { return }
        panel.close()
        self.panel = nil
        Self.visibleCount -= 1
        NotificationManager.shared.stopAlertSound(for: self)
    }
}

// MARK: - Alert Content

/// Centered card: app icon, when, what to do, snooze progress, then "知道了" over the snooze buttons
struct AlertContentView: View {
    let text: AlertText
    var snoozeActions: [AlertAction] = []
    let onDismiss: () -> Void

    private static let radius: CGFloat = 20

    var body: some View {
        VStack(spacing: 0) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 44, height: 44)
                .frame(width: 56, height: 56)
                .background(Theme.brandSoft, in: Circle())

            Text(text.eyebrow)
                .font(.system(size: 13, weight: .medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .padding(.top, 14)

            Text(text.title)
                .font(Theme.Font.title)
                .multilineTextAlignment(.center)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, Theme.Space.xs)

            if let snooze = text.snooze {
                SnoozeDots(snooze: snooze)
                    .padding(.top, Theme.Space.m)
            }

            Button(L("知道了", "Got it"), action: onDismiss)
                .buttonStyle(ChivvyButtonStyle(kind: .primary, size: .large, fill: true))
                .keyboardShortcut(.defaultAction)
                .padding(.top, 20)

            if !snoozeActions.isEmpty {
                HStack(spacing: Theme.Space.s) {
                    ForEach(Array(snoozeActions.enumerated()), id: \.offset) { _, action in
                        Button(action.label, action: action.handler)
                            .buttonStyle(ChivvyButtonStyle(kind: .secondary, size: .regular, fill: true))
                    }
                }
                .padding(.top, Theme.Space.s)
            }

            Text(L("声音 45 秒后自动停止", "The sound stops after 45 seconds"))
                .font(Theme.Font.caption)
                .foregroundStyle(.tertiary)
                .padding(.top, Theme.Space.m)
        }
        .padding(.horizontal, Theme.Space.xl)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(width: 320)
        .panelCard(radius: Self.radius, glow: true)
    }
}

/// ●●○ for snoozes used, with the count spelled out
private struct SnoozeDots: View {
    let snooze: AlertText.Snooze

    var body: some View {
        HStack(spacing: Theme.Space.s) {
            HStack(spacing: Theme.Space.xs) {
                ForEach(0..<SnoozeState.maxCount, id: \.self) { index in
                    Circle()
                        .fill(index < snooze.used ? Theme.brand : Theme.switchOff)
                        .frame(width: 6, height: 6)
                }
            }
            Text(snooze.text)
                .font(.system(size: 12))
                .foregroundStyle(snooze.exhausted ? Theme.brandText : Color.secondary)
        }
        .accessibilityElement(children: .combine)
    }
}
