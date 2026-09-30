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

    /// `secondaryActions` show as grey buttons before "知道了"; each also dismisses the panel.
    func show(title: String = "时间到！", note: String, footnote: String? = nil,
              secondaryActions: [AlertAction] = []) {
        close()

        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 320, height: 0),
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
        let actions = secondaryActions.map { action in
            AlertAction(label: action.label) { dismiss(); action.handler() }
        }
        let content = AlertContentView(title: title, note: note, footnote: footnote,
                                       secondaryActions: actions, onDismiss: dismiss)

        let hostingView = NSHostingView(rootView: content)
        hostingView.frame = NSRect(x: 0, y: 0, width: 320, height: 1)
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

struct AlertContentView: View {
    let title: String
    let note: String
    var footnote: String? = nil
    var secondaryActions: [AlertAction] = []
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 36))
                .foregroundStyle(.orange)
                .padding(.top, 4)

            Text(title)
                .font(.system(size: 24, weight: .semibold))

            if !note.isEmpty {
                Text(note)
                    .font(.system(size: 15))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
            }

            if let footnote {
                Text(footnote)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                ForEach(Array(secondaryActions.enumerated()), id: \.offset) { _, action in
                    Button {
                        action.handler()
                    } label: {
                        Text(action.label)
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.primary)
                            .frame(width: 104, height: 36)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(Color.secondary.opacity(0.15))
                            )
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    onDismiss()
                } label: {
                    Text("知道了")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.white)
                        .frame(width: secondaryActions.count > 1 ? 104 : 120, height: 36)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.orange)
                        )
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(.horizontal, 32)
        .padding(.vertical, 28)
        .frame(minWidth: 320)
        .background(
            VisualEffectBackground()
                .clipShape(RoundedRectangle(cornerRadius: 16))
        )
    }
}

struct VisualEffectBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.state = .active
        view.isEmphasized = true
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}
