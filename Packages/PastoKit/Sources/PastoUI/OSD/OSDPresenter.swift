import AppKit
import SwiftUI

/// Shows brief on-screen notices ("Copied", "Paused"…) in the style of the system's volume
/// indicator.
///
/// Every notice is its own window with its own timer: nothing is queued or replaced, so two
/// notices in quick succession simply overlap.
public enum OSD {
    private enum Metrics {
        static let side: CGFloat = 200
        static let cornerRadius: CGFloat = 20
        /// Distance from the bottom of the screen to the bottom of the notice.
        static let bottomOffset: CGFloat = 140
        /// Above the panel, the Dock and menus.
        static let windowLevel = NSWindow.Level(rawValue: 1000)
        static let holdDuration: TimeInterval = 1.0
        static let fadeDuration: TimeInterval = 0.5
    }

    /// Shows a notice on the next main-actor turn and returns immediately.
    public static func show(symbol: String, title: String?, subtitle: Text? = nil, onClick: (() -> Void)? = nil) {
        Task {
            present(OSDView(symbol: symbol, title: title, subtitle: subtitle, onClick: onClick))
            announce(title)
        }
    }

    /// VoiceOver reads the title as the notice shows: the notice never takes the focus and is
    /// gone in a moment.
    private static func announce(_ title: String?) {
        guard let title, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: title, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
    }

    private static func present(_ view: OSDView) {
        let window = makeWindow(hosting: view)
        window.center()
        if let screen = NSScreen.main {
            window.setFrameOrigin(NSPoint(x: window.frame.minX, y: screen.frame.minY + Metrics.bottomOffset))
        }
        // It appears at once, stays, then fades out; the window only lives as long as these blocks.
        window.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + Metrics.holdDuration) {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = Metrics.fadeDuration
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                window.animator().alphaValue = 0
            } completionHandler: {
                MainActor.assumeIsolated { window.orderOut(nil) }
            }
        }
    }

    private static func makeWindow(hosting view: OSDView) -> NSWindow {
        let background = NSVisualEffectView()
        background.wantsLayer = true
        background.layer?.cornerRadius = Metrics.cornerRadius
        background.material = .hudWindow
        background.blendingMode = .behindWindow
        // Stays vivid while Pasto is not the active application.
        background.state = .active
        background.autoresizingMask = [.width, .height]

        let content = NSHostingView(rootView: view)
        content.translatesAutoresizingMaskIntoConstraints = false
        background.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: background.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: background.trailingAnchor),
            content.topAnchor.constraint(equalTo: background.topAnchor),
            content.bottomAnchor.constraint(equalTo: background.bottomAnchor),
            content.widthAnchor.constraint(equalToConstant: Metrics.side),
            content.heightAnchor.constraint(equalToConstant: Metrics.side),
        ])

        let window = NSWindow(contentRect: .zero, styleMask: [], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.level = Metrics.windowLevel
        window.backgroundColor = .clear
        window.contentView = background
        window.layoutIfNeeded()
        return window
    }
}
