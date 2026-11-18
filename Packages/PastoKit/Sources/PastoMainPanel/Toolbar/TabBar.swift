import AppKit
import PastoCore
import PastoInput
import PastoUI

/// The tabs of the panel: the clipboard history followed by the pinboards, in a strip that scrolls
/// sideways when they do not fit.
///
/// It is given the tabs and the selected one, and reports what the user does with them. A click
/// selects, a double click on a name renames in place and a drag reorders the tabs.
public final class TabBar: LayerBackedView, NSDraggingSource {
    /// A mouse press on a tab, which becomes a drag once the pointer has moved far enough.
    private struct Press {
        let id: ListID
        /// Where the press started, in the window's coordinates.
        let location: NSPoint
    }

    /// A tab on its way to another position, in a dragging session of its own.
    private struct Drag {
        let id: ListID
        let sourceIndex: Int
        /// The position the tab would be dropped at.
        var destinationIndex: Int
    }

    /// What a dragged tab carries: its list's identifier. Only the tab bar takes it.
    private static let tabDragType = NSPasteboard.PasteboardType("jnjambrino.Pasto.tab")

    public private(set) var items: [TabBarItem] = []
    public private(set) var selectedID: ListID?

    /// The user chose a tab, with the mouse or the keyboard. A click on the tab that is already
    /// selected reports it again: the list is to be shown afresh.
    public var onSelect: ((ListID) -> Void)?
    /// The user gave a tab a new name, trimmed. It may be empty: the list is then stored without
    /// one and its tab shows the default name.
    public var onRename: ((_ id: ListID, _ name: String) -> Void)?
    /// The user dragged a tab to another position: every tab's identifier in the new order.
    public var onReorder: (([ListID]) -> Void)?
    /// Cards of the strip were dropped on a pinboard's tab.
    public var onDropItems: ((_ ids: [ItemID], _ pinboard: ListID) -> Void)?

    /// The shortcuts that move to the neighbouring tabs while the panel is key. Nil disables one.
    public var nextPinboardShortcut: Shortcut? = TabBarMetrics.nextPinboardShortcut
    public var previousPinboardShortcut: Shortcut? = TabBarMetrics.previousPinboardShortcut

    /// How many items a list holds, for the tabs' tooltips; without it they have none.
    var itemCount: ((ListID) -> Int)?

    /// Tabs reduced to their icons, which is how they make room for the active search field.
    /// Collapsed tabs can be chosen, but not renamed, reordered or reached with the pinboard
    /// shortcuts.
    public var isCollapsed = false {
        didSet {
            guard isCollapsed != oldValue else { return }
            cancelPressAndDrag()
            editingCell?.commitEditing()
            cells.values.forEach { $0.isCollapsed = isCollapsed }
            invalidateMetrics()
            if isCollapsed {
                // Back to the start, inside the transition that collapses the tabs, if any.
                scrollView.setContentOffset(0, animated: NSAnimationContext.current.allowsImplicitAnimation)
            } else {
                // Once the tabs have their widths back, the selected one is scrolled into view.
                DispatchQueue.main.async { [weak self] in
                    guard let self, !isCollapsed else { return }
                    reveal(selectedID, animated: true)
                }
            }
        }
    }

    /// Hides the selected tab's capsule without changing which tab is selected, as suggestions
    /// mode does while it shows no list. The capsule goes and comes back at once.
    public var isSelectionSuppressed = false {
        didSet {
            guard isSelectionSuppressed != oldValue else { return }
            updateCellSelection()
        }
    }

    /// Builds the context menu of a tab.
    var menuProvider: ((TabBarItem) -> NSMenu?)?

    private let scrollView = TabBarScrollView(frame: .zero)
    private let documentView = NSView(frame: .zero)
    private let leadingOverlay = TabBarEdgeOverlay(frame: .zero)
    private let trailingOverlay = TabBarEdgeOverlay(frame: .zero)

    private var cells: [ListID: TabBarCell] = [:]
    private var press: Press?
    private var drag: Drag?
    /// The tab to scroll into view on the next layout pass, once the widths are final.
    private var idToReveal: ListID?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.documentView = documentView
        scrollView.onScroll = { [weak self] in self?.updateEdgeOverlays() }
        addSubview(scrollView)

        for overlay in [leadingOverlay, trailingOverlay] {
            overlay.isHidden = true
            addSubview(overlay)
        }
        registerForDraggedTypes([Self.tabDragType])
    }

    // MARK: - Accessibility

    // A tab group whose children are the tabs, in order, wherever they sit in the scroll view.

    override public func isAccessibilityElement() -> Bool { true }

    override public func accessibilityRole() -> NSAccessibility.Role? { .tabGroup }

    override public func accessibilityChildren() -> [Any]? {
        items.compactMap { cells[$0.id] }
    }

    override public func accessibilityTabs() -> [Any]? {
        accessibilityChildren()
    }

    // MARK: - Content

    /// Replaces the tabs. Cells are kept by identifier, so a tab that is still there keeps its
    /// state (including a rename in progress).
    ///
    /// Nothing fades: a tab that is gone leaves at once, a new one appears whole in its place, and
    /// the others, the search button and "+" slide to their new places, animated if `animated`.
    public func setItems(_ newItems: [TabBarItem], animated: Bool) {
        cancelPressAndDrag()
        items = newItems

        let newIDs = Set(newItems.map(\.id))
        for (id, cell) in cells where !newIDs.contains(id) {
            cells[id] = nil
            cell.cancelEditing()
            cell.removeFromSuperview()
        }

        var arrivingCells: [TabBarCell] = []
        for item in newItems {
            if let cell = cells[item.id] {
                cell.update(item)
            } else {
                let cell = makeCell(for: item)
                cells[item.id] = cell
                arrivingCells.append(cell)
            }
        }
        updateCellSelection()

        // New tabs start where they end up, laid out already, instead of growing from the origin
        // when the others slide.
        let layout = currentLayout
        for (item, frame) in zip(newItems, layout.cellFrames) {
            guard let cell = cells[item.id], arrivingCells.contains(cell) else { continue }
            cell.frame = frame
            documentView.addSubview(cell)
            cell.layoutSubtreeIfNeeded()
        }

        invalidateMetrics()
        if animated, window != nil {
            animate(duration: TabBarMetrics.reflowDuration)
        }
    }

    /// Changes the selected tab without reporting it through `onSelect`. The capsule jumps to it
    /// at once; only scrolling it into view is animated, if `animated`.
    public func select(_ id: ListID?, animated: Bool) {
        selectedID = id
        updateCellSelection()
        reveal(id, animated: animated)
    }

    /// Moves the selection to the tab after the selected one; from the last tab, to the first.
    public func selectNext() {
        selectNeighbour(offset: 1)
    }

    /// Moves the selection to the tab before the selected one; from the first tab, to the last.
    public func selectPrevious() {
        selectNeighbour(offset: -1)
    }

    /// Turns a tab's name into an editable field, as "+" and the tab's menu do: focus leaves
    /// whatever had it, the tab is scrolled into view, animated, and the editing starts when the
    /// scrolling ends.
    public func beginRenaming(_ id: ListID) {
        guard cells[id] != nil else { return }
        window?.makeFirstResponder(nil)
        reveal(id, animated: true) { [weak self] in
            guard let self, let cell = cells[id], !isCollapsed else { return }
            layoutSubtreeIfNeeded()
            cell.beginEditing()
        }
    }

    /// A double click on a name starts editing it there and then, without scrolling.
    private func beginRenamingInPlace(_ id: ListID) {
        editingCell?.commitEditing()
        cells[id]?.beginEditing()
    }

    /// While a name is typed its tab grows or shrinks at once and its trailing edge stays in view.
    private func editingWidthDidChange(_ id: ListID) {
        invalidateMetrics()
        guard let cell = cells[id], !isCollapsed else { return }
        (superview ?? self).layoutSubtreeIfNeeded()
        let offset = currentLayout.scrollOffset(
            revealingTrailingEdgeOf: cell.frame,
            from: scrollView.contentOffset,
            visibleWidth: scrollView.frame.width
        )
        if offset != scrollView.contentOffset {
            scrollView.setContentOffset(offset, animated: false)
        }
    }

    private func selectNeighbour(offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == selectedID }) else { return }
        let id = items[(index + offset + items.count) % items.count].id
        // With a single tab the neighbour is the tab itself, and there is nothing to change.
        guard id != selectedID else { return }
        select(id, animated: true)
        onSelect?(id)
        announceTab(id)
    }

    /// VoiceOver says which tab ⌘← or ⌘→ moved to and how many items its list holds: the focus
    /// stays where it was, so nothing else would tell.
    private func announceTab(_ id: ListID) {
        guard NSWorkspace.shared.isVoiceOverEnabled,
              let item = items.first(where: { $0.id == id }),
              let count = itemCount?(id)
        else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: ToolbarStrings.tabAnnouncement(name: item.name, itemCount: count),
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
    }

    /// A click selects, and on the selected tab selects it again.
    private func didClick(_ id: ListID) {
        if id != selectedID {
            select(id, animated: true)
        }
        onSelect?(id)
    }

    private var editingCell: TabBarCell? {
        cells.values.first(where: \.isEditing)
    }

    private func updateCellSelection() {
        for (id, cell) in cells {
            cell.setSelected(id == selectedID && !isSelectionSuppressed)
        }
    }

    private func makeCell(for item: TabBarItem) -> TabBarCell {
        let cell = TabBarCell(item: item)
        cell.isCollapsed = isCollapsed
        cell.setAccessibilityParent(self)
        let id = item.id
        cell.menuProvider = { [weak self] in
            guard let self, let item = items.first(where: { $0.id == id }) else { return nil }
            return menuProvider?(item)
        }
        cell.onSelect = { [weak self] in self?.didClick(id) }
        cell.onBeginRenaming = { [weak self] in self?.beginRenamingInPlace(id) }
        cell.onPreferredWidthChange = { [weak self] in self?.editingWidthDidChange(id) }
        cell.onEndEditing = { [weak self] newName in self?.didEndRenaming(id, newName: newName) }
        cell.onDropItems = { [weak self] ids in self?.onDropItems?(ids, id) }
        cell.toolTipProvider = { [weak self] in self?.toolTip(for: id) }
        return cell
    }

    private func didEndRenaming(_ id: ListID, newName: String?) {
        // The field may have grown or shrunk while typing, whatever the outcome.
        invalidateMetrics()
        guard let newName, let index = items.firstIndex(where: { $0.id == id }) else { return }
        items[index].name = TabBarItem.displayName(newName, kind: items[index].kind)
        onRename?(id, newName)
    }

    /// What a tab says under the pointer, worked out when it is about to show: how many items
    /// its list holds and, when both are set, the shortcuts that move between tabs.
    private func toolTip(for id: ListID) -> String? {
        guard let count = itemCount?(id) else { return nil }
        guard let previous = previousPinboardShortcut, let next = nextPinboardShortcut else {
            return ToolbarStrings.itemCount(count)
        }
        return ToolbarStrings.tabToolTip(
            itemCount: count,
            previousShortcut: ShortcutDisplay.string(for: previous),
            nextShortcut: ShortcutDisplay.string(for: next)
        )
    }

    // MARK: - Layout

    /// The tabs in the order they are drawn: during a drag, with the dragged tab already where it
    /// would be dropped, which is what opens the gap for it.
    private var displayItems: [TabBarItem] {
        guard let drag else { return items }
        return TabBarReorder.moving(items, from: drag.sourceIndex, to: drag.destinationIndex)
    }

    private func cellWidths(of items: [TabBarItem]) -> [CGFloat] {
        items.map { cells[$0.id]?.preferredWidth ?? 0 }
    }

    private var currentLayout: TabBarLayout {
        TabBarLayout(cellWidths: cellWidths(of: displayItems))
    }

    /// The width at which every tab shows. The toolbar centres the bar using it.
    override public var intrinsicContentSize: NSSize {
        NSSize(width: currentLayout.intrinsicWidth, height: TabBarMetrics.scrollHeight)
    }

    /// The tabs' widths changed: lay them out again and let the toolbar place the bar again.
    private func invalidateMetrics() {
        invalidateIntrinsicContentSize()
        needsLayout = true
        superview?.needsLayout = true
    }

    override public func layout() {
        super.layout()
        // The strip is centred vertically; the overlays flank it, outside the scrolling area.
        let overlayWidth = TabBarMetrics.edgeOverlayWidth
        let stripHeight = TabBarMetrics.scrollHeight
        let stripY = (bounds.height - stripHeight) / 2
        scrollView.frame = NSRect(
            x: overlayWidth,
            y: stripY,
            width: max(bounds.width - 2 * overlayWidth, 0),
            height: stripHeight
        )
        leadingOverlay.frame = NSRect(x: 0, y: stripY, width: overlayWidth, height: stripHeight)
        trailingOverlay.frame = NSRect(x: bounds.width - overlayWidth, y: stripY, width: overlayWidth, height: stripHeight)

        let layout = currentLayout
        documentView.setFrameSize(layout.contentSize)
        for (item, frame) in zip(displayItems, layout.cellFrames) {
            cells[item.id]?.frame = frame
        }

        if let id = idToReveal, let index = displayItems.firstIndex(where: { $0.id == id }) {
            let offset = layout.scrollOffset(
                revealing: layout.cellFrames[index],
                from: scrollView.contentOffset,
                visibleWidth: scrollView.frame.width
            )
            if offset != scrollView.contentOffset {
                // Animated when this pass runs inside one of the bar's transitions.
                scrollView.setContentOffset(offset, animated: NSAnimationContext.current.allowsImplicitAnimation)
            }
        }
        idToReveal = nil
        updateEdgeOverlays()
    }

    /// Each overlay shows, at once, while more than the content's inset is hidden beyond its end
    /// of the strip.
    private func updateEdgeOverlays() {
        let visible = scrollView.documentVisibleRect
        let threshold = TabBarMetrics.edgeOverlayThreshold
        leadingOverlay.isHidden = visible.minX <= threshold
        trailingOverlay.isHidden = documentView.frame.width - threshold <= visible.maxX
    }

    // MARK: - Transitions

    /// Scrolls the tab `id` into view on the next layout pass: animated, with the reveal's
    /// duration, if `animated`. `completion` runs when the scrolling ends, or at once if it is
    /// not animated.
    private func reveal(_ id: ListID?, animated: Bool, completion: (@MainActor () -> Void)? = nil) {
        idToReveal = id
        needsLayout = true
        guard animated, window != nil else {
            completion?()
            return
        }
        animate(duration: TabBarMetrics.revealDuration, completion: completion)
    }

    /// Runs the pending layout as one animation, easing out, with `duration` or, when nil, the
    /// system's default. The layout pass starts at the superview so that the toolbar's other
    /// elements move along when the bar's width changes.
    private func animate(duration: TimeInterval?, completion: (@MainActor () -> Void)? = nil) {
        NSAnimationContext.runAnimationGroup { context in
            if let duration {
                context.duration = duration
            }
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            (superview ?? self).layoutSubtreeIfNeeded()
        } completionHandler: {
            MainActor.assumeIsolated { completion?() }
        }
    }

    // MARK: - Keyboard

    /// The pinboard shortcuts, after whatever the views inside want with the key. They work
    /// while a name is being edited too, but not while a search is active.
    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        if super.performKeyEquivalent(with: event) {
            return true
        }
        guard event.type == .keyDown, !isCollapsed else { return false }
        if matches(event, previousPinboardShortcut) {
            selectPrevious()
            return true
        }
        if matches(event, nextPinboardShortcut) {
            selectNext()
            return true
        }
        return false
    }

    private func matches(_ event: NSEvent, _ shortcut: Shortcut?) -> Bool {
        guard let shortcut else { return false }
        // Arrow keys carry flags of their own (function, numeric pad) that are not modifiers.
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        return Int(event.keyCode) == shortcut.keyCode && modifiers == shortcut.modifiers
    }

    // MARK: - Mouse

    // A tab handles its own clicks and passes the press on. Here the press is remembered, in
    // case it becomes a drag, and continues up the responder chain, so that the panel can hand
    // keyboard focus back to the item strip.

    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        editingCell?.commitEditing()
        let point = documentView.convert(event.locationInWindow, from: nil)
        press = cell(at: point).map { Press(id: $0.item.id, location: event.locationInWindow) }
    }

    override public func mouseDragged(with event: NSEvent) {
        super.mouseDragged(with: event)
        // Any tab moves, the history's too, but not while the tabs are collapsed.
        guard let press, !isCollapsed, let cell = cells[press.id],
              let sourceIndex = items.firstIndex(where: { $0.id == press.id })
        else { return }
        let location = event.locationInWindow
        guard hypot(location.x - press.location.x, location.y - press.location.y) >= TabBarMetrics.dragThreshold
        else { return }

        self.press = nil
        beginDragging(cell, from: sourceIndex, with: event)
    }

    private func cell(at point: NSPoint) -> TabBarCell? {
        guard scrollView.documentVisibleRect.contains(point) else { return nil }
        return cells.values.first { $0.frame.contains(point) }
    }

    /// Forgets a press or a drag in progress, for when the tabs change under the pointer. The
    /// dragging session itself cannot be ended from here: its drop is then refused.
    private func cancelPressAndDrag() {
        press = nil
        endDrag()
    }

    // MARK: - Reordering

    // A tab is moved in a dragging session: its picture travels with the pointer while the tab
    // itself, out of sight, sits where it would be dropped, which opens the gap for it. The order
    // changes only when it is dropped on the bar. Taking the pointer off the bar leaves the gap
    // where it is; dropped anywhere else, the picture does not fly back: it goes, and the tab
    // shows again in its place at once.

    private func beginDragging(_ cell: TabBarCell, from sourceIndex: Int, with event: NSEvent) {
        let id = cell.item.id
        let pasteboardItem = NSPasteboardItem()
        pasteboardItem.setString(id.rawValue, forType: Self.tabDragType)
        let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
        // The picture is taken before the tab is hidden.
        cell.isPressed = false
        draggingItem.setDraggingFrame(convert(cell.bounds, from: cell), contents: cell.makeDragImage())

        cell.alphaValue = TabBarMetrics.draggedCellOpacity
        // No tab says anything under the pointer while one is being dragged.
        cells.values.forEach { $0.showsToolTip = false }
        drag = Drag(id: id, sourceIndex: sourceIndex, destinationIndex: sourceIndex)
        let session = beginDraggingSession(with: [draggingItem], event: event, source: self)
        session.animatesToStartingPositionsOnCancelOrFail = false
    }

    /// Opens the gap at `destinationIndex`, moving the other tabs out of the way.
    private func moveDraggedTab(to destinationIndex: Int) {
        guard let drag, drag.destinationIndex != destinationIndex else { return }
        self.drag?.destinationIndex = destinationIndex
        // Near an end of a strip that scrolls, the gap is what brings more tabs into view.
        reveal(drag.id, animated: true)
    }

    /// Ends the drag with the tabs in the order they had, at once. After a drop that was taken
    /// there is no drag left to end.
    private func endDrag() {
        guard let drag else { return }
        self.drag = nil
        cells[drag.id]?.alphaValue = 1
        needsLayout = true
        layoutSubtreeIfNeeded()
    }

    public func draggingSession(
        _ session: NSDraggingSession,
        sourceOperationMaskFor context: NSDraggingContext
    ) -> NSDragOperation {
        context == .withinApplication ? .move : []
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        endDrag()
        for cell in cells.values {
            cell.showsToolTip = true
            // The tab under the pointer, the dropped one perhaps, lights up again.
            cell.updateTrackingAreas()
        }
        // After any drag of a tab, wherever it ended, the app is made active again.
        DispatchQueue.main.asyncAfter(deadline: .now() + TabBarMetrics.reactivationDelay) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    override public func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        draggingUpdated(sender)
    }

    override public func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard let drag else { return [] }
        moveDraggedTab(to: TabBarReorder.destinationIndex(
            cellFrames: currentLayout.cellFrames,
            currentIndex: drag.destinationIndex,
            pointer: documentView.convert(sender.draggingLocation, from: nil)
        ))
        return .move
    }

    override public func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        guard let drag else { return false }
        self.drag = nil
        let reordered = TabBarReorder.moving(items, from: drag.sourceIndex, to: drag.destinationIndex)
        let changed = reordered != items
        items = reordered
        // The tab is already in its slot: it only has to show again.
        cells[drag.id]?.alphaValue = 1
        needsLayout = true
        if changed {
            onReorder?(reordered.map(\.id))
        }
        return true
    }
}
