import AppKit
import PastoCore
import PastoFoundation
import QuartzCore

/// Owns one stack from the moment it opens until it closes: its model, its window and where that
/// window is.
final class StackWindowController: NSWindowController, NSWindowDelegate {
    /// Under which AppKit remembers where the user left the window.
    private static let frameAutosaveName = "PastoStackFrame"

    let model: StackModel
    /// Called once, after the window has closed.
    var onClose: (() -> Void)?

    private let config: ConfigStore
    private let state: StackPanelState
    private let hostingView: StackHostingView
    private let rowDragging: StackRowDragging

    /// The move of the panel in progress, if any.
    private var drag: StackDrag?
    /// From the panel's origin to the window's, fixed for the length of a move.
    private var windowOriginFromPanel = CGPoint.zero
    /// The part of the panel's position a window cannot have: windows sit on whole points, so
    /// the content is shifted inside the window by the rest.
    private var contentShift = CGPoint.zero

    init(model: StackModel, config: ConfigStore, dependencies: StackDependencies) {
        self.model = model
        self.config = config
        // The real limit depends on the screen the window turns out to be on.
        state = StackPanelState(heightLimit: StackMetrics.Window.minimumHeightLimit)
        rowDragging = StackRowDragging(model: model, state: state, dependencies: dependencies)
        hostingView = StackHostingView(rootView: StackView(model: model, state: state, dragging: rowDragging), state: state)
        rowDragging.view = hostingView
        hostingView.rowDragging = rowDragging
        hostingView.registerForDraggedTypes(StackDropContent.acceptedTypes)

        let panel = StackPanel()
        panel.contentView = hostingView
        super.init(window: panel)

        panel.setFrameAutosaveName(Self.frameAutosaveName)
        // Forced, so that a position on a screen that is no longer there is still honoured the
        // way AppKit sees fit.
        panel.setFrameUsingName(Self.frameAutosaveName, force: true)
        panel.delegate = self
        panel.mouseDownInterceptor = { [weak hostingView] event in
            hostingView?.handleMouseDown(event) ?? false
        }
        hostingView.onMove = { [weak self] in self?.handle($0) }
        hostingView.onResize = { [weak self] in self?.resize(toPanelHeight: $0) }
        model.onCloseRequest = { [weak self] in self?.close() }

        applyHeightLimit()
        followPanelFrame()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("StackWindowController is created in code")
    }

    override func close() {
        model.tearDown()
        rowDragging.tearDown()
        super.close()
        // Frees the name for the next stack's window.
        window?.setFrameAutosaveName("")
        let onClose = onClose
        self.onClose = nil
        onClose?()
    }

    // MARK: - Height

    /// Sizes the window for the height limit in force, keeping its top-left corner in place.
    /// Until the user resizes the panel, the limit follows the screen the window is on.
    private func applyHeightLimit() {
        guard let window else { return }
        let screens = NSScreen.screens
        let index = StackWindowLayout.screenIndex(forWindowFrame: window.frame, screenFrames: screens.map(\.frame))
        guard let screen = index.map({ screens[$0] }) ?? NSScreen.main else { return }

        let heightLimit = StackWindowLayout.heightLimit(
            stored: config.value(for: .pasteStackHeightLimit),
            visibleScreenHeight: screen.visibleFrame.height
        )
        let frame = StackWindowLayout.windowFrame(current: window.frame, heightLimit: heightLimit)
        if frame != window.frame {
            window.setFrame(frame, display: true)
        }
        if state.heightLimit != heightLimit {
            state.heightLimit = heightLimit
        }
    }

    /// Rows join at the bottom, so a panel left low on the screen would grow past its edge:
    /// the window moves up by what would be hidden, as far as the top of the screen allows.
    private func keepPanelOnScreen() {
        guard drag == nil, let window, let panel = hostingView.panelFrameOnScreen,
              let screen = window.screen ?? NSScreen.main
        else { return }
        let visible = screen.visibleFrame
        let hidden = visible.minY + StackMetrics.Panel.margin - panel.minY
        let room = visible.maxY - StackMetrics.Panel.margin - panel.maxY
        let shift = min(hidden, room)
        guard shift >= 1 else { return }
        window.setFrameOrigin(NSPoint(x: window.frame.minX, y: window.frame.minY + shift.rounded(.up)))
    }

    private func followPanelFrame() {
        // After the layout pass that reported the frame, when the window can be moved.
        state.onPanelFrameChange = { [weak self] in
            DispatchQueue.main.async { self?.keepPanelOnScreen() }
        }
    }

    /// Saved on every step of the drag, not when it ends.
    private func resize(toPanelHeight height: CGFloat) {
        config.set(Double(StackWindowLayout.resizedHeightLimit(height)), for: .pasteStackHeightLimit)
        applyHeightLimit()
    }

    func windowDidMove(_ notification: Notification) {
        applyHeightLimit()
    }

    func windowDidChangeScreen(_ notification: Notification) {
        applyHeightLimit()
    }

    // MARK: - Moving

    private func handle(_ move: StackPanelMove) {
        switch move.phase {
        case .began: beginMove(move)
        case .moved: continueMove(move)
        case .ended: endMove()
        }
    }

    private func beginMove(_ move: StackPanelMove) {
        guard let window, let panelFrame = hostingView.panelFrameOnScreen else { return }
        let guides = SnapGuideBuilder.guides(
            screens: NSScreen.screens.map(\.visibleFrame),
            windows: SnapWindowList.onScreen(),
            ownWindowNumber: window.windowNumber
        )
        // AppKit must not save the positions the window goes through on its way.
        window.setFrameAutosaveName("")
        drag = StackDrag(
            pointer: move.pointer,
            time: move.time,
            panelFrame: panelFrame.offsetBy(dx: contentShift.x, dy: contentShift.y),
            guides: guides
        )
        windowOriginFromPanel = CGPoint(x: window.frame.minX - panelFrame.minX, y: window.frame.minY - panelFrame.minY)
    }

    private func continueMove(_ move: StackPanelMove) {
        guard let window, var drag else { return }
        let panelOrigin = drag.moved(pointer: move.pointer, time: move.time, isSnappingOn: move.isSnappingOn)
        self.drag = drag

        let position = CGPoint(x: panelOrigin.x + windowOriginFromPanel.x, y: panelOrigin.y + windowOriginFromPanel.y)
        let aligned = StackWindowLayout.pixelAligned(position, scale: window.backingScaleFactor)
        contentShift = aligned.contentShift

        // Window and content move in the same frame, or the panel would shimmer.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        window.setFrameOrigin(aligned.windowOrigin)
        hostingView.layer?.setAffineTransform(CGAffineTransform(translationX: contentShift.x, y: contentShift.y))
        CATransaction.commit()
        CATransaction.flush()
    }

    private func endMove() {
        guard let window, drag != nil else { return }
        drag = nil
        window.saveFrame(usingName: Self.frameAutosaveName)
        window.setFrameAutosaveName(Self.frameAutosaveName)
        window.setFrame(window.frame, display: true)
    }
}
