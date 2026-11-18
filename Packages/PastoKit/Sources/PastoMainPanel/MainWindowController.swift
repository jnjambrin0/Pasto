import AppKit
import PastoCoreUI

/// Shows and hides the clipboard panel.
///
/// The window appears at its final frame immediately; what animates is the content view, which
/// slides up from below the screen edge and back down when closing — or, with "Reduce motion",
/// fades in and out where it stands.
public final class MainWindowController: NSWindowController {
    /// True once the opening animation has finished, false once the closing one has.
    public private(set) var isPanelVisible = false

    /// Called when the opening animation finishes.
    public var onDidShow: (() -> Void)?
    /// Called when closing starts, before the closing animation.
    public var onWillClose: (() -> Void)?
    /// Called once the closing animation has finished and the window is gone.
    public var onDidClose: (() -> Void)?

    /// What Undo and Redo act on while the panel is key: the window hands it to whoever asks
    /// for its undo manager, which is how ⌘Z and ⇧⌘Z, sent up the responder chain by the main
    /// menu, reach it.
    public var contentUndoManager: UndoManager?

    /// One-shot: set before presenting an auxiliary window so that the resulting loss of key
    /// status does not close the panel.
    public var pendingResignKeyCloseSuppression = false

    /// Incremented when a show or hide starts, so the completion of an interrupted animation
    /// cannot apply its end state over the transition that replaced it.
    private var transitionGeneration = 0
    private var isClosing = false
    private weak var originalScreen: NSScreen?

    public init(contentView: NSView) {
        super.init(window: MainWindow(contentView: contentView))
        // The panel exists from launch and takes in captures before it is first shown, each of
        // which scrolls the strip to the new item: it gets its on-screen size now, so that
        // scrolling is not worked out against a window narrower than a card.
        if let window, let screen = NSScreen.main {
            window.setFrame(panelFrame(on: screen, height: window.frame.height), display: false)
            window.layoutIfNeeded()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("MainWindowController is created in code")
    }

    /// True when the panel is on screen and not on its way out.
    public var isOpen: Bool {
        window?.isVisible == true && !isClosing
    }

    /// Pressing the shortcut while the panel is closing reopens it.
    public func toggle() {
        if isOpen {
            close()
        } else {
            showWindow(nil)
        }
    }

    override public func showWindow(_ sender: Any?) {
        guard let screen = NSScreen.main, let window, let contentView = window.contentView else { return }

        transitionGeneration += 1
        let generation = transitionGeneration
        isClosing = false

        // The panel spans the full screen frame, covering the Dock area.
        let height = contentView.frame.height
        window.backgroundColor = .clear
        window.setFrame(panelFrame(on: screen, height: height), display: false)
        window.makeFirstResponder(nil)
        // What paused while the panel was closed catches up before it is drawn.
        NotificationCenter.default.post(name: WindowVisibility.willShowNotification, object: window)
        super.showWindow(sender)
        originalScreen = screen

        contentView.superview?.clipsToBounds = true
        // Park the content just below the window, full size, and let it slide up. Assigning the
        // frame inside the group is enough: implicit animation does the rest.
        let size = NSSize(width: window.frame.width, height: height)
        let reducesMotion = Self.reducesMotion
        // A fade that was interrupted leaves the content transparent: a slide starts it opaque.
        contentView.alphaValue = reducesMotion ? 0 : 1
        contentView.frame = NSRect(origin: NSPoint(x: 0, y: reducesMotion ? 0 : -height), size: size)
        NSAnimationContext.runAnimationGroup { context in
            if reducesMotion {
                context.duration = MainPanelMetrics.reducedMotionFadeDuration
                contentView.animator().alphaValue = 1
                return
            }
            let points = MainPanelMetrics.showTimingControlPoints
            context.duration = MainPanelMetrics.showDuration
            context.timingFunction = CAMediaTimingFunction(controlPoints: points.0, points.1, points.2, points.3)
            context.allowsImplicitAnimation = true
            contentView.frame = NSRect(origin: .zero, size: size)
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionGeneration == generation else { return }
                self.isPanelVisible = true
                self.onDidShow?()
            }
        }
    }

    override public func close() {
        guard let window, window.isVisible, !isClosing, let contentView = window.contentView else { return }

        transitionGeneration += 1
        let generation = transitionGeneration
        window.makeFirstResponder(nil)
        isClosing = true
        stopWatchingAttachedWindow()
        onWillClose?()

        contentView.superview?.clipsToBounds = false
        let reducesMotion = Self.reducesMotion
        NSAnimationContext.runAnimationGroup { context in
            if reducesMotion {
                context.duration = MainPanelMetrics.reducedMotionFadeDuration
                contentView.animator().alphaValue = 0
                return
            }
            context.duration = MainPanelMetrics.hideDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            context.allowsImplicitAnimation = true
            contentView.animator().setFrameOrigin(NSPoint(x: 0, y: -contentView.frame.height))
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.transitionGeneration == generation else { return }
                self.finishClosing()
            }
        }
    }

    private func finishClosing() {
        super.close()
        originalScreen = nil
        isClosing = false
        isPanelVisible = false
        window?.contentView?.superview?.clipsToBounds = true
        window?.contentView?.alphaValue = 1
        onDidClose?()
    }

    /// "Reduce motion" in System Settings › Accessibility › Display: the panel fades in and out
    /// in place instead of sliding the height of the screen's bottom edge.
    private static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    // MARK: - Window events

    func windowDidResignKey() {
        if pendingResignKeyCloseSuppression {
            pendingResignKeyCloseSuppression = false
            return
        }
        guard let window, window.sheets.isEmpty, NSApp.modalWindow == nil else { return }
        if let attached = attachedWindowTakingKeyFromClick(in: window) {
            keepOpen(whileKeyIn: attached)
            return
        }
        close()
    }

    // MARK: - Windows attached to the panel

    // A click in the text of the preview's popover gives it the keyboard and the panel stays
    // open. The popover hangs from the panel as a child window; while it holds the keyboard the
    // panel waits, and once it lets go the panel takes the keyboard back or, if it went anywhere
    // else, closes as it would have.

    /// Watches the attached window that holds the keyboard instead of the panel.
    private var attachedKeyObservation: (any NSObjectProtocol)?

    /// The child window of the panel that a mouse press is making key, if that is why the panel
    /// is losing the keyboard.
    private func attachedWindowTakingKeyFromClick(in window: NSWindow) -> NSWindow? {
        guard let event = NSApp.currentEvent,
              [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type),
              let clicked = event.window, clicked.parent === window
        else { return nil }
        return clicked
    }

    private func keepOpen(whileKeyIn attached: NSWindow) {
        stopWatchingAttachedWindow()
        attachedKeyObservation = NotificationCenter.default.addObserver(
            forName: NSWindow.didResignKeyNotification,
            object: attached,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.attachedWindowDidResignKey() }
        }
    }

    private func stopWatchingAttachedWindow() {
        attachedKeyObservation.map(NotificationCenter.default.removeObserver)
        attachedKeyObservation = nil
    }

    /// Where the keyboard went is known on the next turn.
    private func attachedWindowDidResignKey() {
        stopWatchingAttachedWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self, let window, isOpen, !window.isKeyWindow else { return }
            if let key = NSApp.keyWindow {
                if key.parent === window {
                    keepOpen(whileKeyIn: key)
                } else if window.sheets.isEmpty, NSApp.modalWindow == nil {
                    // Another window: the preview dragged out of its popover, for one.
                    close()
                }
            } else if NSApp.isActive {
                // The attached window closed with the keyboard (Esc in the preview): back to
                // the panel, whose strip shows its focus again.
                window.makeKey()
            } else {
                // A click in another application.
                close()
            }
        }
    }

    func windowDidChangeScreen() {
        // Only while the panel is up: `originalScreen` is nil when it is closed.
        guard let window, let originalScreen, let screen = window.screen, screen != originalScreen,
              let contentView = window.contentView
        else { return }
        window.setFrame(panelFrame(on: screen, height: contentView.frame.height), display: true)
        self.originalScreen = screen
    }

    private func panelFrame(on screen: NSScreen, height: CGFloat) -> NSRect {
        NSRect(x: screen.frame.minX, y: screen.frame.minY, width: screen.frame.width, height: height)
    }
}
