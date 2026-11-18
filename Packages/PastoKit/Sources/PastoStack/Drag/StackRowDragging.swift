import AppKit
import PastoCore
import PastoCoreUI
import QuartzCore
import SwiftUI

/// Rows dragged out of the panel, around it and into it.
///
/// A row travels in an AppKit dragging session, so that any application can take it: it gets
/// what a paste of the row would write, and the row leaves the stack. Over the panel, the session
/// reorders the rows as it goes. The card does not travel as the session's image but in a window
/// of its own, which follows the pointer and, when the drag ends on the panel or comes to nothing,
/// glides back into the row's slot.
///
/// The panel is also where drags from elsewhere land: items dragged from Pasto's panel join the
/// stack as they are, and content dragged from another application is stored as an item first.
final class StackRowDragging: NSObject, NSDraggingSource {
    /// The view sessions start from and drops arrive at.
    weak var view: StackHostingView?

    private let model: StackModel
    private let state: StackPanelState
    private let lookUpItems: StackModel.ItemLookup
    private let draggingContents: StackDependencies.DraggingContents?
    private let record: StackDependencies.Record?

    /// The card of the row in flight, while its session lasts.
    private var liftedWindow: StackLiftedCardWindow?
    /// From the pointer to the lifted window's origin, fixed for the length of a session.
    private var liftedWindowOffset = CGSize.zero
    private var didDropInPanel = false
    private var landing: Landing?
    /// A dragging session does not keep its source alive, and the panel may close while a row is
    /// still in flight: the source holds on to itself until its session has ended.
    private var keptAliveDuringSession: StackRowDragging?
    /// Set once the panel has closed.
    private var isTornDown = false

    init(model: StackModel, state: StackPanelState, dependencies: StackDependencies) {
        self.model = model
        self.state = state
        lookUpItems = dependencies.items
        draggingContents = dependencies.draggingContents
        record = dependencies.record
    }

    /// The panel is closing: nothing of a drag may stay on screen. A session still open ends on
    /// its own, and then changes nothing.
    func tearDown() {
        isTornDown = true
        endLanding()
        liftedWindow?.orderOut(nil)
        liftedWindow = nil
        state.dropIndex = nil
    }

    // MARK: - Source

    /// Starts dragging a row with the event in progress. The row's drag gesture calls this on
    /// every step; only the first opens a session.
    func beginDragging(_ row: StackRow) {
        guard !isTornDown, state.draggedRowID == nil, let view, let event = NSApp.currentEvent,
              let cardFrame = state.cardFrames[row.id]
        else { return }
        endLanding()

        let liftedFrame = cardFrame.insetBy(dx: -StackMetrics.Drag.imagePadding, dy: -StackMetrics.Drag.imagePadding)
        let draggingItems = pasteboardWriters(for: row.item).map { writer in
            let item = NSDraggingItem(pasteboardWriter: writer)
            // Without contents: the card travels in a window of its own.
            item.setDraggingFrame(view.viewRect(fromPanel: liftedFrame), contents: nil)
            return item
        }
        liftCard(of: row, from: liftedFrame, in: view)
        didDropInPanel = false
        model.beginDrag(row.id)
        state.draggedRowID = row.id
        keptAliveDuringSession = self

        let session = view.beginDraggingSession(with: draggingItems, event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    /// What a paste of the item would write, plus its identifier. An item with nothing to give
    /// other applications can still be dragged around Pasto.
    private func pasteboardWriters(for item: Item) -> [ItemPasteboardWriter] {
        let content = draggingContents?([item.id], model.pasteOptions)[item.id] ?? []
        guard !content.isEmpty else { return [ItemPasteboardWriter(itemID: item.id, content: nil)] }
        return content.map { ItemPasteboardWriter(itemID: item.id, content: $0) }
    }

    /// Puts the row's card in a window just above the panel, over its slot.
    private func liftCard(of row: StackRow, from liftedFrame: CGRect, in view: StackHostingView) {
        let content = StackCardContent(item: row.item, isPlainText: model.isPlainTextOn, isLinkPreviewsOn: model.isLinkPreviewsOn)
        let scale = view.window?.backingScaleFactor ?? 2
        guard let screenFrame = view.screenRect(fromPanel: liftedFrame),
              let image = StackDragImage.make(of: content, appearance: view.effectiveAppearance, scale: scale)
        else { return }

        let panelLevel = view.window?.level ?? .statusBar
        let level = NSWindow.Level(rawValue: panelLevel.rawValue + 1)
        let window = StackLiftedCardWindow(image: image, origin: screenFrame.origin, level: level)
        window.orderFrontRegardless()
        let pointer = NSEvent.mouseLocation
        liftedWindowOffset = CGSize(width: screenFrame.minX - pointer.x, height: screenFrame.minY - pointer.y)
        liftedWindow = window
    }

    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        // Other applications get a copy; inside Pasto the row moves.
        context == .outsideApplication ? .copy : .move
    }

    func draggingSession(_ session: NSDraggingSession, willBeginAt screenPoint: NSPoint) {
        // The card leaves the list in the frame its window appears in: nothing to animate.
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.liftedRowID = state.draggedRowID }
    }

    func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        liftedWindow?.setFrameOrigin(NSPoint(
            x: screenPoint.x + liftedWindowOffset.width,
            y: screenPoint.y + liftedWindowOffset.height
        ))
    }

    /// Settles the row: dropped outside, it has left the stack and its card goes with it;
    /// otherwise the card glides to the row's slot — where the drag left it, or, for a drag that
    /// came to nothing, where it started.
    func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        defer { keptAliveDuringSession = nil }
        let window = liftedWindow
        liftedWindow = nil
        guard let rowID = state.draggedRowID, !isTornDown else {
            window?.orderOut(nil)
            return
        }
        state.draggedRowID = nil

        let outcome = StackDragOutcome(operation: operation, didDropInPanel: didDropInPanel)
        model.endDrag(outcome)
        if let window, outcome != .droppedOutside {
            land(window, on: rowID)
        } else {
            window?.orderOut(nil)
            reveal(rowID)
        }
        // The pointer moved during the session without the panel hearing of it.
        view?.updateHoveredRow()
    }

    // MARK: - Landing

    /// The card on its way back into its row's slot.
    private struct Landing {
        let window: StackLiftedCardWindow
        let rowID: StackRow.ID
        let startFrame: CGRect
        let startTime: CFTimeInterval
        let displayLink: CADisplayLink
        /// The slot has been reached: the row shows in the list again and the window fades.
        var isRevealing = false
    }

    private func land(_ window: StackLiftedCardWindow, on rowID: StackRow.ID) {
        guard let contentView = window.contentView else {
            window.orderOut(nil)
            reveal(rowID)
            return
        }
        let displayLink = contentView.displayLink(target: self, selector: #selector(stepLanding))
        displayLink.add(to: .main, forMode: .common)
        landing = Landing(
            window: window,
            rowID: rowID,
            startFrame: window.frame,
            startTime: CACurrentMediaTime(),
            displayLink: displayLink
        )
    }

    @objc private func stepLanding(_ displayLink: CADisplayLink) {
        guard var landing, landing.displayLink === displayLink else {
            displayLink.invalidate()
            return
        }
        // Looked up on every frame: the slot moves if the list does. A row that is gone, or a
        // panel no longer on screen, ends the landing.
        guard let target = slotFrame(of: landing.rowID) else {
            endLanding()
            return
        }

        let progress = min(1, (displayLink.targetTimestamp - landing.startTime) / StackMetrics.Drag.landingDuration)
        let eased = CGFloat(StackMetrics.Drag.landingCurve.value(at: progress))
        landing.window.setFrame(Self.interpolate(from: landing.startFrame, to: target, by: eased), display: true)
        guard !landing.isRevealing else { return }
        let liftedOpacity = StackMetrics.Drag.liftedOpacity
        landing.window.alphaValue = liftedOpacity + (1 - liftedOpacity) * progress
        guard progress >= 1 else { return }

        landing.isRevealing = true
        self.landing = landing
        let window = landing.window
        // A change that changes nothing would never report its completion.
        guard state.liftedRowID == landing.rowID else {
            fadeOut(window)
            return
        }
        // The row shows in the list again, and only then does the window over it fade away.
        withAnimation(nil, completionCriteria: .logicallyComplete) {
            state.liftedRowID = nil
        } completion: { [weak self] in
            self?.fadeOut(window)
        }
    }

    private func fadeOut(_ window: StackLiftedCardWindow) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = StackMetrics.Drag.landedFadeDuration
            window.animator().alphaValue = 0
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // A new drag may have ended this landing meanwhile.
                guard let self, self.landing?.window === window else { return }
                self.endLanding()
            }
        }
    }

    /// Puts away the card of the landing in progress, if any, and shows its row in the list.
    private func endLanding() {
        guard let landing else { return }
        self.landing = nil
        landing.displayLink.invalidate()
        landing.window.orderOut(nil)
        reveal(landing.rowID)
    }

    /// The row's card shows in the list again, at once.
    private func reveal(_ rowID: StackRow.ID) {
        guard state.liftedRowID == rowID else { return }
        var transaction = Transaction()
        transaction.disablesAnimations = true
        withTransaction(transaction) { state.liftedRowID = nil }
    }

    /// Where a row's card is on screen, with the room its picture has around it; `nil` once the
    /// row is gone or the panel is not on screen.
    private func slotFrame(of rowID: StackRow.ID) -> CGRect? {
        guard let view, view.window?.isVisible == true, let cardFrame = state.cardFrames[rowID] else { return nil }
        let padding = StackMetrics.Drag.imagePadding
        return view.screenRect(fromPanel: cardFrame.insetBy(dx: -padding, dy: -padding))
    }

    private static func interpolate(from start: CGRect, to end: CGRect, by fraction: CGFloat) -> CGRect {
        func mix(_ a: CGFloat, _ b: CGFloat) -> CGFloat { a + (b - a) * fraction }
        return CGRect(
            x: mix(start.minX, end.minX),
            y: mix(start.minY, end.minY),
            width: mix(start.width, end.width),
            height: mix(start.height, end.height)
        )
    }

    // MARK: - Destination

    /// A drag is over the panel, at `point` in the panel's coordinates. Returns what letting it
    /// go would do.
    func dragMoved(_ info: any NSDraggingInfo, to point: CGPoint) -> NSDragOperation {
        guard !isTornDown else { return [] }
        if let rowID = ownDraggedRow(of: info) {
            // The other rows make way as the pointer goes.
            let otherCards = model.rows.filter { $0.id != rowID }.compactMap { state.cardFrames[$0.id] }
            model.move(rowID, to: StackReorder.index(forPointerY: point.y, among: otherCards))
            return .move
        }

        let operation = StackDropContent.operation(
            forSourceMask: info.draggingSourceOperationMask,
            carriesItems: StackDropContent.carriesItems(info.draggingPasteboard)
        )
        guard !operation.isEmpty else { return [] }
        let index = StackReorder.index(forPointerY: point.y, among: model.rows.compactMap { state.cardFrames[$0.id] })
        if state.dropIndex != index { state.dropIndex = index }
        return operation
    }

    /// A drag has left the panel, or ended without being dropped on it: its gap closes.
    func dragExited() {
        if state.dropIndex != nil { state.dropIndex = nil }
    }

    /// A drag is let go over the panel. Returns whether the panel took it.
    func drop(_ info: any NSDraggingInfo) -> Bool {
        // A row of the stack is already where the pointer left it; the end of its session
        // settles it.
        if ownDraggedRow(of: info) != nil {
            didDropInPanel = true
            return true
        }
        guard !isTornDown, let index = state.dropIndex else { return false }
        state.dropIndex = nil

        let pasteboard = info.draggingPasteboard
        let ids = ItemDragType.itemIDs(in: pasteboard)
        let items = ids.isEmpty ? [] : lookUpItems(ids)
        if !items.isEmpty {
            // Pasto's items join the stack as they are; the history does not change.
            model.insert(items, at: index)
            return true
        }

        // Anything else becomes one new item, however many pieces the drag holds.
        let content = StackDropContent.foreignContent(of: pasteboard)
        guard let record, !content.isEmpty else { return false }
        Task { [weak self] in
            guard let id = await record(content), let self, !isTornDown, let item = lookUpItems([id]).first else { return }
            model.insert([item], at: index)
        }
        return true
    }

    /// The row this panel is dragging, when `info` is about that drag.
    private func ownDraggedRow(of info: any NSDraggingInfo) -> StackRow.ID? {
        info.draggingSource as AnyObject? === self ? state.draggedRowID : nil
    }
}
