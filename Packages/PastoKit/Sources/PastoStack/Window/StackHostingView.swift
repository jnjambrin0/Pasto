import AppKit
import PastoUI
import QuartzCore
import SwiftUI

/// The view that fills the stack's window. Besides hosting the SwiftUI panel it deals with the
/// pointer where SwiftUI cannot: moving and resizing the panel, letting clicks through the
/// transparent margin, knowing which row is under the pointer while Pasto is not the active
/// application, and taking drops.
final class StackHostingView: NSHostingView<StackView> {
    /// Receives the steps of a move of the panel.
    var onMove: ((StackPanelMove) -> Void)?
    /// Receives the panel height a resize asks for.
    var onResize: ((CGFloat) -> Void)?
    /// Handles what is dragged over the panel.
    var rowDragging: StackRowDragging?

    private let state: StackPanelState
    /// The pointer position of the last move step sent, while the panel is being moved.
    private var lastPointer: CGPoint?

    init(rootView: StackView, state: StackPanelState) {
        self.state = state
        super.init(rootView: rootView)
        // The window's size is decided by the height limit, not by the content.
        sizingOptions = []
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .mouseMoved, .activeAlways, .inVisibleRect],
            owner: self
        ))
        // Rows move under a still pointer when the list scrolls or changes.
        state.onCardFramesChange = { [weak self] in self?.updateHoveredRow() }
    }

    @available(*, unavailable)
    required init(rootView: StackView) {
        fatalError("StackHostingView needs the panel's state")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StackHostingView is created in code")
    }

    // MARK: - Coordinates

    /// A window location in the coordinate space the panel's views report their frames in: the
    /// view's own, with y growing downwards.
    private func panelPoint(fromWindow location: NSPoint) -> CGPoint {
        let point = convert(location, from: nil)
        return isFlipped ? point : CGPoint(x: point.x, y: bounds.height - point.y)
    }

    /// A rectangle the panel's views reported, in this view's own coordinates.
    func viewRect(fromPanel rect: CGRect) -> CGRect {
        var frame = rect
        if !isFlipped { frame.origin.y = bounds.height - frame.maxY }
        return frame
    }

    /// A rectangle the panel's views reported, in screen coordinates; `nil` while the view is in
    /// no window.
    func screenRect(fromPanel rect: CGRect) -> CGRect? {
        guard let window else { return nil }
        return window.convertToScreen(convert(viewRect(fromPanel: rect), to: nil))
    }

    /// The visible panel in screen coordinates; `nil` while the view is in no window.
    var panelFrameOnScreen: CGRect? {
        screenRect(fromPanel: state.panelFrame)
    }

    // MARK: - Hit testing

    /// The first click on the panel should act, even though its window is never key.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Clicks on the transparent margin around the panel go to whatever is behind the window.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let location = superview?.convert(point, to: nil) ?? point
        guard state.hitTest.isInsidePanel(panelPoint(fromWindow: location)) else { return nil }
        return super.hitTest(point)
    }

    private func isOverControl(atWindow location: NSPoint) -> Bool {
        let point = superview?.convert(location, from: nil) ?? location
        var view = super.hitTest(point)
        while let candidate = view {
            if candidate is NSControl || candidate is ToolbarButton { return true }
            view = candidate.superview
        }
        return false
    }

    // MARK: - Moving and resizing

    /// Takes a press of the primary button if it is for the panel itself: on its bottom edge it
    /// resizes, on its empty surface it moves. Returns false for presses meant for rows, buttons
    /// or the windows behind. Runs its own event loop until the button is released.
    func handleMouseDown(_ event: NSEvent) -> Bool {
        let target = state.hitTest.target(
            at: panelPoint(fromWindow: event.locationInWindow),
            isOverControl: isOverControl(atWindow: event.locationInWindow)
        )
        guard target != .passThrough else { return false }

        state.isTrackingPanel = true
        if target == .resize {
            trackResize()
        } else {
            trackMove()
        }
        state.isTrackingPanel = false
        updatePointer(atWindow: window?.mouseLocationOutsideOfEventStream ?? event.locationInWindow)
        return true
    }

    /// The pointer is read on every frame rather than from the drag events, which arrive at their
    /// own pace: the panel then keeps up with the display.
    private func trackMove() {
        sendMove(.began)
        lastPointer = NSEvent.mouseLocation
        let displayLink = displayLink(target: self, selector: #selector(displayLinkDidFire))
        displayLink.add(to: .main, forMode: .common)

        window?.trackEvents(matching: [.leftMouseUp, .leftMouseDragged], timeout: .infinity, mode: .eventTracking) { event, stop in
            if event?.type != .leftMouseDragged { stop.pointee = true }
        }

        displayLink.invalidate()
        followPointer()
        lastPointer = nil
        sendMove(.ended)
    }

    @objc private func displayLinkDidFire(_: CADisplayLink) {
        followPointer()
    }

    private func followPointer() {
        guard let lastPointer, NSEvent.mouseLocation != lastPointer else { return }
        self.lastPointer = NSEvent.mouseLocation
        sendMove(.moved)
    }

    private func sendMove(_ phase: StackPanelMove.Phase) {
        onMove?(StackPanelMove(
            phase: phase,
            pointer: NSEvent.mouseLocation,
            time: CACurrentMediaTime(),
            isSnappingOn: !NSEvent.modifierFlags.contains(.option)
        ))
    }

    /// Dragging the bottom edge changes how tall the panel may get.
    private func trackResize() {
        let initialHeight = state.panelFrame.height
        let initialPointerY = NSEvent.mouseLocation.y
        window?.trackEvents(matching: [.leftMouseUp, .leftMouseDragged], timeout: .infinity, mode: .eventTracking) { [weak self] event, stop in
            guard event?.type == .leftMouseDragged else {
                stop.pointee = true
                return
            }
            self?.onResize?(initialHeight + initialPointerY - NSEvent.mouseLocation.y)
        }
    }

    // MARK: - Pointer

    override func mouseMoved(with event: NSEvent) {
        super.mouseMoved(with: event)
        updatePointer(atWindow: event.locationInWindow)
    }

    override func mouseExited(with event: NSEvent) {
        super.mouseExited(with: event)
        NSCursor.arrow.set()
        setHoveredRow(nil)
    }

    private func updatePointer(atWindow location: NSPoint) {
        let hitTest = state.hitTest
        let point = panelPoint(fromWindow: location)
        (hitTest.isOnResizeEdge(point) ? NSCursor.resizeUpDown : NSCursor.arrow).set()
        setHoveredRow(hitTest.isInsidePanel(point) ? hitTest.row(at: point) : nil)
    }

    /// Works out again which row is under the pointer, wherever the pointer is: for when the rows
    /// move under it rather than it over them. The cursor is left alone — the pointer may well
    /// be over another application.
    func updateHoveredRow() {
        guard let window else { return }
        let point = panelPoint(fromWindow: window.convertPoint(fromScreen: NSEvent.mouseLocation))
        let hitTest = state.hitTest
        setHoveredRow(hitTest.isInsidePanel(point) ? hitTest.row(at: point) : nil)
    }

    private func setHoveredRow(_ rowID: StackRow.ID?) {
        if state.hoveredRowID != rowID { state.hoveredRowID = rowID }
    }

    // MARK: - Dropping

    // The panel takes drops itself; SwiftUI's own handling of drops is not used.

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        rowDragging?.dragMoved(sender, to: panelPoint(fromWindow: sender.draggingLocation)) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        rowDragging?.dragMoved(sender, to: panelPoint(fromWindow: sender.draggingLocation)) ?? []
    }

    override func draggingExited(_ sender: (any NSDraggingInfo)?) {
        rowDragging?.dragExited()
    }

    override func prepareForDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        true
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        rowDragging?.drop(sender) ?? false
    }

    override func concludeDragOperation(_ sender: (any NSDraggingInfo)?) {}

    /// A drag given up over the panel may not report leaving it.
    override func draggingEnded(_ sender: any NSDraggingInfo) {
        rowDragging?.dragExited()
    }
}
