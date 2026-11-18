import AppKit

/// The stack's window: a transparent, non-activating panel that floats over everything, on every
/// Space, and never takes the keyboard — the application being pasted into keeps the focus.
final class StackPanel: NSPanel {
    /// Offered every press of the primary button before anyone else. Returns whether it used it.
    var mouseDownInterceptor: ((NSEvent) -> Bool)?

    init() {
        // The size comes later, from the height limit; the origin only matters the first time.
        let origin = StackMetrics.Window.initialTopLeft
        super.init(
            contentRect: NSRect(origin: origin, size: .zero),
            styleMask: .nonactivatingPanel,
            backing: .buffered,
            defer: true
        )
        isOpaque = false
        backgroundColor = .clear
        // The panel's glass casts its own shadow, inside the window's transparent margin.
        hasShadow = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isRestorable = false
        allowsToolTipsWhenApplicationIsInactive = true
        autorecalculatesKeyViewLoop = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        // The window moves itself, with snapping; see `StackHostingView`.
        isMovableByWindowBackground = false
        // A document window's animation, not a utility one's.
        animationBehavior = .documentWindow
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    override func sendEvent(_ event: NSEvent) {
        if event.type == .leftMouseDown, mouseDownInterceptor?(event) == true { return }
        super.sendEvent(event)
    }
}
