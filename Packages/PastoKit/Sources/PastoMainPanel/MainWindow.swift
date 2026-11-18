import AppKit

/// The clipboard panel window: a non-activating panel at main-menu level, so it floats above the
/// Dock and takes key focus for keyboard navigation while the application the user was working
/// in stays frontmost and receives the synthetic ⌘V.
///
/// Only the attributes the panel needs are set here; everything else keeps `NSPanel`'s default.
final class MainWindow: NSPanel, NSWindowDelegate {
    init(contentView: NSView) {
        super.init(
            contentRect: .zero,
            styleMask: [.resizable, .nonactivatingPanel],
            backing: .buffered,
            defer: true
        )
        self.contentView = contentView
        autorecalculatesKeyViewLoop = true
        level = .mainMenu
        isMovable = false
        hasShadow = false
        delegate = self
        restoreSavedHeight()
        layoutIfNeeded()
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }

    /// Pins the size limits to the current size, so the `.resizable` style never lets the system
    /// resize the panel on its own: the only way to change its height is the resize handle.
    override func layoutIfNeeded() {
        super.layoutIfNeeded()
        minSize = frame.size
        maxSize = frame.size
    }

    /// `makeFirstResponder(nil)` falls back to the initial first responder, then the content view.
    override func makeFirstResponder(_ responder: NSResponder?) -> Bool {
        super.makeFirstResponder(responder ?? initialFirstResponder ?? contentView)
    }

    override func performClose(_ sender: Any?) {
        windowController?.close()
    }

    /// A window without a close button refuses Close in the menu, which would leave ⌘W dead.
    /// This is the method a menu asks first.
    override func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        menuItem.action == #selector(performClose(_:)) || super.validateMenuItem(menuItem)
    }

    // MARK: - Height

    /// Follows the resize handle during a drag, growing upwards from the fixed bottom edge.
    func liveResize(toHeight proposedHeight: CGFloat) {
        setHeight(PanelHeight.rubberBanded(proposedHeight), display: false, animate: false)
    }

    /// Settles inside the allowed range when the drag ends, and remembers the result.
    func endResize() {
        setHeight(PanelHeight.clamped(frame.height), display: true, animate: true)
        saveHeight()
    }

    func resetHeight() {
        guard frame.height != MainPanelMetrics.defaultHeight else { return }
        setHeight(MainPanelMetrics.defaultHeight, display: true, animate: true)
        saveHeight()
    }

    private func setHeight(_ height: CGFloat, display: Bool, animate: Bool) {
        var frame = frame
        frame.size.height = height
        setFrame(frame, display: display, animate: animate)
    }

    private func saveHeight() {
        saveFrame(usingName: MainPanelMetrics.frameAutosaveName)
    }

    private func restoreSavedHeight() {
        if setFrameUsingName(MainPanelMetrics.frameAutosaveName) { return }
        guard frame.height != MainPanelMetrics.defaultHeight else { return }
        var frame = frame
        frame.size.height = MainPanelMetrics.defaultHeight
        setFrame(frame, display: true, animate: false)
        saveHeight()
    }

    // MARK: - NSWindowDelegate

    func windowWillReturnUndoManager(_ window: NSWindow) -> UndoManager? {
        (windowController as? MainWindowController)?.contentUndoManager
    }

    func windowDidResignKey(_ notification: Notification) {
        (windowController as? MainWindowController)?.windowDidResignKey()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        (windowController as? MainWindowController)?.windowDidChangeScreen()
    }
}
