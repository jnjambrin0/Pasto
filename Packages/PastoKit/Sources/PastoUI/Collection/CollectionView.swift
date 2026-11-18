import AppKit

public protocol CollectionViewDataSource: AnyObject {
    func numberOfCells(in collectionView: CollectionView) -> Int
    /// Returns a configured cell obtained from `dequeueReusableCell(_:)`.
    func collectionView(_ collectionView: CollectionView, cellAt index: Int) -> CollectionViewCell
    /// Refreshes a visible cell whose content changed.
    func collectionView(_ collectionView: CollectionView, reconfigure cell: CollectionViewCell, at index: Int)
}

public protocol CollectionViewDelegate: AnyObject {
    /// A single or double click on a cell, after the selection has been updated.
    func collectionView(_ collectionView: CollectionView, didClickCellAt index: Int, with event: NSEvent)
    /// The context menu for a right click on a cell. The cell is part of the selection: a right
    /// click on a cell outside it selects that cell alone, and one inside it leaves it as it is.
    func collectionView(_ collectionView: CollectionView, menuForCellAt index: Int) -> NSMenu?
    /// What dragging the cells at `indexes` puts on the dragging pasteboard: for every index, in
    /// the order given, one writer per dragging item. No writers at all means the cells cannot
    /// be dragged.
    func collectionView(_ collectionView: CollectionView, pasteboardWritersForCellsAt indexes: [Int]) -> [[any NSPasteboardWriting]]
    /// The cells at `indexes` were dropped inside the collection, in front of the cell at
    /// `destination` (the cell count when dropped after the last one). Only called while
    /// `isReorderingEnabled` is set.
    func collectionView(_ collectionView: CollectionView, moveCellsAt indexes: [Int], to destination: Int)
    /// What VoiceOver offers on the cell at `index` besides pressing it and its menu. The cell is
    /// part of the selection by the time an action runs: one outside it becomes the selection
    /// alone, as with a right click.
    func collectionView(_ collectionView: CollectionView, accessibilityActionsForCellAt index: Int) -> [NSAccessibilityCustomAction]
    /// VoiceOver pressed the cell at `index`, which is now the selection alone, as a double
    /// click leaves it. Returns whether the press did anything.
    func collectionView(_ collectionView: CollectionView, accessibilityPressCellAt index: Int) -> Bool
}

extension CollectionViewDelegate {
    // A delegate that does not care about dragging gets a collection whose cells stay put.

    public func collectionView(_ collectionView: CollectionView, pasteboardWritersForCellsAt indexes: [Int]) -> [[any NSPasteboardWriting]] {
        []
    }

    public func collectionView(_ collectionView: CollectionView, moveCellsAt indexes: [Int], to destination: Int) {}

    public func collectionView(_ collectionView: CollectionView, accessibilityActionsForCellAt index: Int) -> [NSAccessibilityCustomAction] {
        []
    }

    public func collectionView(_ collectionView: CollectionView, accessibilityPressCellAt index: Int) -> Bool {
        false
    }
}

/// A horizontally scrolling strip of square, recycled cells with selection, keyboard navigation
/// and animated content changes.
///
/// It deliberately is not `NSCollectionView`: controlling its tiling, selection and scrolling
/// rules exactly is only practical with a view of its own.
open class CollectionView: NSView {
    private enum Metrics {
        /// A recycled cell is kept only if fewer than this many of its type are already waiting.
        static let reuseQueueLimit = 3
        /// How long a plain click on an already selected cell waits before collapsing a
        /// multiple selection, so that the selection can be dragged instead.
        static let dragWaitInterval: TimeInterval = 0.45
        /// Breathing room kept beyond a cell that is scrolled into view, as a multiple of the spacing.
        static let scrollMarginFactor: CGFloat = 1.5
    }

    public weak var dataSource: (any CollectionViewDataSource)?
    public weak var delegate: (any CollectionViewDelegate)?

    public var layoutConfiguration: CollectionContentLayout.Configuration {
        didSet {
            if layoutConfiguration != oldValue { needsLayout = true }
        }
    }

    /// Shown instead of the cells while the collection is empty.
    public var emptyPlaceholderView: NSView? {
        didSet {
            oldValue?.removeFromSuperview()
            if let emptyPlaceholderView {
                addSubview(emptyPlaceholderView)
                emptyPlaceholderView.isHidden = cellCount != 0
                needsLayout = true
            }
        }
    }

    /// A view that scrolls with the cells, at the leading edge of the content. Its owner gives
    /// it its frame, in the content's coordinates, and makes room for it with the leading inset
    /// of `layoutConfiguration`.
    public var leadingAccessoryView: NSView? {
        didSet {
            guard leadingAccessoryView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let leadingAccessoryView {
                scrollContainer.documentView.addSubview(leadingAccessoryView)
            }
        }
    }

    /// Whether the cells can be dropped back on the collection to change their order. The
    /// owner registers the dragged types it writes; the collection accepts only its own drags.
    public var isReorderingEnabled = false

    public private(set) var cellCount = 0
    public private(set) var selection = CollectionSelection()
    public private(set) var contentLayout: CollectionContentLayout

    let scrollContainer = CollectionScrollContainer(frame: .zero)
    /// Where the press that may become a drag started, in the view's coordinates: set by a
    /// single click on a cell and cleared when the drag begins, so there is one drag per press.
    var initialDragLocation: NSPoint?
    /// Shows where a drop would put the dragged cells; created on the first reordering drag.
    var insertionCursor: InsertionCursorView?
    private var visibleCells: [Int: CollectionViewCell] = [:]
    private var reusableCells: [String: [CollectionViewCell]] = [:]
    private var isFirstResponder = false
    private var dragWaitTimer: Timer?
    /// Cells fading out, keyed by the transition that removes them, until its animation ends.
    private var departingCellsByTransition: [Int: [CollectionViewCell]] = [:]
    private var nextTransitionID = 0
    /// The scroll that the latest change of selection started is on its way to the cell.
    private var isScrollingToSelection = false
    /// Tells the scroll to the selection apart from the one it replaced.
    private var selectionScrollID = 0
    /// Waiting for the scroll to the selection to end (`whenSelectionScrollEnds`).
    private var selectionScrollObservers: [(_ finished: Bool) -> Void] = []

    public init(layoutConfiguration: CollectionContentLayout.Configuration) {
        self.layoutConfiguration = layoutConfiguration
        contentLayout = CollectionContentLayout(configuration: layoutConfiguration, boundsSize: .zero, cellCount: 0)
        super.init(frame: .zero)

        scrollContainer.autoresizingMask = [.width, .height]
        scrollContainer.onScroll = { [weak self] in self?.updateVisibleCells() }
        addSubview(scrollContainer)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("CollectionView is created in code")
    }

    // MARK: - Cells

    /// Returns a recycled cell of the given type, or a new one.
    public func dequeueReusableCell<Cell: CollectionViewCell>(_ type: Cell.Type) -> Cell {
        if let cell = reusableCells[Self.reuseKey(for: type)]?.popLast() as? Cell {
            cell.resetVisualState()
            return cell
        }
        return type.init(frame: .zero)
    }

    /// The cell showing `index`, if it is currently on screen.
    public func cell(at index: Int) -> CollectionViewCell? {
        visibleCells[index]
    }

    public var visibleCellsByIndex: [Int: CollectionViewCell] {
        visibleCells
    }

    private static func reuseKey(for type: CollectionViewCell.Type) -> String {
        String(describing: type)
    }

    private func recycle(_ cell: CollectionViewCell) {
        cell.removeFromSuperview()
        let key = Self.reuseKey(for: type(of: cell))
        guard reusableCells[key, default: []].count < Metrics.reuseQueueLimit else { return }
        cell.prepareForReuse()
        reusableCells[key, default: []].append(cell)
    }

    private func makeCell(at index: Int) -> CollectionViewCell {
        guard let dataSource else { preconditionFailure("Must set data source before inserting cells") }
        var cell: CollectionViewCell?
        effectiveAppearance.performAsCurrentDrawingAppearance {
            cell = dataSource.collectionView(self, cellAt: index)
        }
        guard let cell else { preconditionFailure("Data source returned no cell") }
        cell.isEmphasized = showsKeyboardFocus
        cell.isSelected = selection.contains(index)
        cell.frame = contentLayout.frame(forCellAt: index)
        cell.wantsLayer = true
        scrollContainer.documentView.addSubview(cell)
        // The cells sit inside the scroll container, but they are the list's elements.
        cell.setAccessibilityParent(self)
        cellDidAppear(cell)
        return cell
    }

    /// Hook for subclasses; called when a cell is put on screen, configured and in place.
    open func cellDidAppear(_ cell: CollectionViewCell) {}

    // MARK: - Content

    /// Discards everything and asks the data source again: first cell selected, scrolled to the start.
    public func reloadData() {
        for cell in visibleCells.values { recycle(cell) }
        visibleCells.removeAll(keepingCapacity: true)

        cellCount = dataSource?.numberOfCells(in: self) ?? 0
        selection.reset(cellCount: cellCount)
        scrollContainer.setContentOffsetSilently(.zero)
        relayout()
        emptyPlaceholderView?.isHidden = cellCount != 0
        selectionDidChange()
        announceSelectionForAccessibility()
    }

    /// Applies a content change. The data source must already reflect the new content.
    ///
    /// Cells follow their items to their new places, cells whose item is gone fade out on their
    /// way to where the gap closes and cells for positions that come into view fade in, all in
    /// one animation group — but only when a deletion, an insertion or a move actually lands on
    /// screen, and not with Reduce Motion on.
    public func apply(_ changeset: CollectionChangeset, animated: Bool) {
        let map = changeset.indexMap()

        reusableCells.removeAll()
        cellCount = dataSource?.numberOfCells(in: self) ?? 0
        contentLayout.cellCount = cellCount
        selection.remap(cellCount: cellCount) { map.newIndex(forOldIndex: $0) }
        // A shorter document can pull the scroll position back. The cells are still keyed by
        // their old indexes at this point, so the scroll handler must not tile them.
        scrollContainer.performWithoutScrollEvents {
            scrollContainer.documentView.setFrameSize(contentLayout.documentSize)
        }
        let finalRange = contentLayout.visibleIndexes(in: scrollContainer.visibleDocumentRect)

        var cellsAfterTransition: [Int: CollectionViewCell] = [:]
        // Each leaving cell with the position it slides to as it fades.
        var departures: [(cell: CollectionViewCell, compactedIndex: Int)] = []
        for (oldIndex, cell) in visibleCells {
            if let newIndex = map.newIndex(forOldIndex: oldIndex) {
                cellsAfterTransition[newIndex] = cell
            } else {
                departures.append((cell, map.compactedIndex(forOldIndex: oldIndex)))
            }
        }
        let departingCells = departures.map(\.cell)
        // Updated cells are refreshed in place.
        for index in changeset.updates {
            guard let cell = cellsAfterTransition[index] else { continue }
            dataSource?.collectionView(self, reconfigure: cell, at: index)
        }

        // Every position that ends up on screen without a cell gets one, fading in: the
        // changeset's own insertions, and the neighbours that slide into view to fill a gap.
        // Those entering past the last cell that stays start further out by the number of
        // cells that are leaving, so they travel together with the ones closing the gap.
        let lastStayingIndex = cellsAfterTransition.keys.filter { finalRange?.contains($0) == true }.max() ?? 0
        let insertions = Set(changeset.insertions)
        var hasArrivingCells = false
        for index in finalRange.map(Array.init) ?? [] where cellsAfterTransition[index] == nil {
            let cell = makeCell(at: index)
            cell.alphaValue = 0
            if !insertions.contains(index), index > lastStayingIndex {
                cell.frame = contentLayout.frame(forCellAt: index + departingCells.count)
            }
            cellsAfterTransition[index] = cell
            hasArrivingCells = true
        }
        visibleCells = cellsAfterTransition

        let changesVisibleCells = !departingCells.isEmpty || hasArrivingCells
            || changeset.moves.contains { finalRange?.contains($0.to) == true }

        let applyFinalState = { [contentLayout] in
            for (index, cell) in cellsAfterTransition {
                cell.frame = contentLayout.frame(forCellAt: index)
                cell.alphaValue = 1
            }
            for (cell, index) in departures {
                cell.frame = contentLayout.frame(forCellAt: index)
                cell.alphaValue = 0
            }
        }
        let transitionID = nextTransitionID
        nextTransitionID += 1
        departingCellsByTransition[transitionID] = departingCells

        // With Reduce Motion the cards do not slide: the change shows at once.
        if animated, changesVisibleCells, !Animator.reducesMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                context.allowsImplicitAnimation = true
                applyFinalState()
            } completionHandler: { [weak self] in
                MainActor.assumeIsolated { self?.finishTransition(transitionID) }
            }
        } else {
            applyFinalState()
            finishTransition(transitionID)
        }

        refreshSelectionState()
        emptyPlaceholderView?.isHidden = cellCount != 0
        selectionDidChange()
    }

    private func finishTransition(_ transitionID: Int) {
        for cell in departingCellsByTransition.removeValue(forKey: transitionID) ?? [] {
            recycle(cell)
        }
        // Cells that slid out of view, and neighbours that should now be visible, are sorted
        // out on the next turn of the run loop.
        DispatchQueue.main.async { [weak self] in self?.updateVisibleCells() }
    }

    // MARK: - Selection

    /// Hook for subclasses; called after the selection changes.
    open func selectionDidChange() {}

    public func select(_ index: Int, mode: CollectionSelection.Mode = .single, animated: Bool) {
        guard selection.indexes != [index] else { return }
        selection.select(index, mode: mode, cellCount: cellCount)
        refreshSelectionState()
        selectionDidChange()
        if let cursor = selection.cursor {
            scrollToSelection(at: cursor, animated: animated)
        }
        announceSelectionForAccessibility()
    }

    /// Calls `body` once the scroll that the latest change of selection started is over, with
    /// false if another scroll took over first. At once when no such scroll is on its way: it has
    /// ended, or part of the cell was already showing.
    public func whenSelectionScrollEnds(_ body: @escaping (_ finished: Bool) -> Void) {
        guard isScrollingToSelection else { return body(true) }
        selectionScrollObservers.append(body)
    }

    /// Brings the cell the selection moved to into view, and tells `whenSelectionScrollEnds`
    /// when it is there.
    private func scrollToSelection(at cursor: Int, animated: Bool) {
        // A scroll still on its way to an earlier selection gives way to this one.
        endSelectionScroll(finished: false)
        guard (0..<cellCount).contains(cursor) else { return }
        selectionScrollID += 1
        let scrollID = selectionScrollID
        isScrollingToSelection = true
        scrollToCell(at: cursor, animated: animated) { [weak self] finished in
            guard let self, scrollID == selectionScrollID else { return }
            endSelectionScroll(finished: finished)
        }
    }

    private func endSelectionScroll(finished: Bool) {
        guard isScrollingToSelection else { return }
        isScrollingToSelection = false
        let observers = selectionScrollObservers
        selectionScrollObservers = []
        for observer in observers { observer(finished) }
    }

    override open func selectAll(_ sender: Any?) {
        selection.selectAll(cellCount: cellCount)
        refreshSelectionState()
        selectionDidChange()
        announceSelectionForAccessibility()
    }

    private func refreshSelectionState() {
        for (index, cell) in visibleCells {
            cell.isSelected = selection.contains(index)
        }
    }

    // MARK: - Scrolling

    /// Brings a cell fully into view, leaving a margin beyond it; does nothing if it already fits.
    /// `completion` receives false when another scroll took over before this one arrived.
    public func scrollToCell(at index: Int, animated: Bool, completion: ((_ finished: Bool) -> Void)? = nil) {
        guard (0..<cellCount).contains(index) else { return }
        let visible = scrollContainer.visibleDocumentRect
        let frame = contentLayout.frame(forCellAt: index)
        let spacing = layoutConfiguration.interitemSpacing
        let margin = Metrics.scrollMarginFactor * spacing

        var targetX: CGFloat
        if visible.maxX < frame.maxX {
            targetX = frame.minX - (visible.width - contentLayout.stride - margin)
        } else if frame.minX < visible.minX {
            targetX = frame.minX - (margin + spacing)
        } else {
            completion?(true)
            return
        }
        // Near either end of the content the margin cannot be had: the clip view would stop the
        // content short of the target, and the animation, aimed beyond, would look cut and
        // hurried. It is aimed where the content will actually stop.
        let range = scrollContainer.horizontalOffsetRange
        targetX = min(max(targetX, range.lowerBound), range.upperBound)

        // When part of the cell is already showing there is nothing to wait for.
        let isPartlyVisible = frame.intersects(visible)
        if isPartlyVisible { completion?(true) }
        scrollContainer.setContentOffset(
            CGPoint(x: targetX, y: scrollContainer.contentOffset.y),
            animated: animated,
            completion: isPartlyVisible ? nil : completion
        )
    }

    /// How far the cell at `index` starts from the leading edge of the visible area; nil when
    /// the cell is not on screen.
    public func leadingOffset(ofCellAt index: Int) -> CGFloat? {
        visibleCells[index].map { $0.frame.minX - scrollContainer.contentOffset.x }
    }

    /// Scrolls, without animation, so that the cell at `index` starts `leadingOffset` from the
    /// leading edge of the visible area: where another cell was, to keep a card in place on
    /// screen across a change of content. The position is set directly: nothing keeps it within
    /// the content.
    public func scrollToCell(at index: Int, leadingOffset: CGFloat) {
        guard (0..<cellCount).contains(index) else { return }
        let x = contentLayout.frame(forCellAt: index).minX - leadingOffset
        scrollContainer.setContentOffset(CGPoint(x: x, y: scrollContainer.contentOffset.y), animated: false)
    }

    // MARK: - Layout and tiling

    override open func layout() {
        super.layout()
        relayout()
        emptyPlaceholderView?.frame = bounds
    }

    private func relayout() {
        let previousLayout = contentLayout
        let newLayout = CollectionContentLayout(configuration: layoutConfiguration, boundsSize: bounds.size, cellCount: cellCount)
        guard newLayout != previousLayout || visibleCells.isEmpty else { return }
        contentLayout = newLayout

        // Keep the first visible cell where it is while the cells change size: the document is
        // resized before the offset when growing and after it when shrinking, so the offset is
        // always valid.
        let anchor = visibleCells.keys.min().flatMap { $0 >= 1 ? $0 : nil }
        let adjustOffset = { [scrollContainer] in
            guard let anchor else { return }
            let shift = newLayout.frame(forCellAt: anchor).minX - previousLayout.frame(forCellAt: anchor).minX
            guard shift != 0 else { return }
            var offset = scrollContainer.contentOffset
            offset.x += shift
            scrollContainer.setContentOffsetSilently(offset)
        }
        if newLayout.contentWidth > previousLayout.contentWidth {
            scrollContainer.documentView.setFrameSize(newLayout.documentSize)
            adjustOffset()
        } else {
            adjustOffset()
            scrollContainer.documentView.setFrameSize(newLayout.documentSize)
        }

        for (index, cell) in visibleCells {
            cell.frame = newLayout.frame(forCellAt: index)
        }
        updateVisibleCells()
    }

    /// Cells resolve colours and images for the current appearance when they are configured, so
    /// a switch between light and dark makes all of them again.
    override open func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        for cell in visibleCells.values { recycle(cell) }
        visibleCells.removeAll(keepingCapacity: true)
        updateVisibleCells()
    }

    /// Materialises the cells that should be on screen and recycles the ones that left.
    private func updateVisibleCells() {
        let range = contentLayout.visibleIndexes(in: scrollContainer.visibleDocumentRect)
        for (index, cell) in visibleCells where range?.contains(index) != true {
            visibleCells[index] = nil
            recycle(cell)
        }
        guard let range else { return }
        for index in range where visibleCells[index] == nil && index < cellCount {
            visibleCells[index] = makeCell(at: index)
        }
        if let index = pendingAccessibilityFocusIndex, let cell = visibleCells[index] {
            pendingAccessibilityFocusIndex = nil
            NSAccessibility.post(element: cell, notification: .focusedUIElementChanged)
        }
    }

    // MARK: - Accessibility

    // The collection is a horizontal list whose elements are the cells on screen; VoiceOver
    // reaches the others the way the keyboard does, by moving the selection.

    override open func isAccessibilityElement() -> Bool { true }

    override open func accessibilityRole() -> NSAccessibility.Role? { .list }

    override open func accessibilityOrientation() -> NSAccessibilityOrientation { .horizontal }

    override open func accessibilityChildren() -> [Any]? {
        if cellCount == 0, let emptyPlaceholderView { return [emptyPlaceholderView] }
        let accessory: [Any] = leadingAccessoryView.map { $0.isHidden ? [] : [$0] } ?? []
        return accessory + visibleCells.sorted { $0.key < $1.key }.map(\.value)
    }

    override open func accessibilityVisibleChildren() -> [Any]? {
        accessibilityChildren()
    }

    override open func accessibilitySelectedChildren() -> [Any]? {
        visibleCells.filter { selection.contains($0.key) }.sorted { $0.key < $1.key }.map(\.value)
    }

    /// While the collection has the keys, the focus VoiceOver follows is the selected cell.
    /// AppKit asks on the main thread, as it does for every other accessibility attribute.
    nonisolated override open var accessibilityFocusedUIElement: Any? {
        let element: NSView = MainActor.assumeIsolated {
            guard showsKeyboardFocus, let cursor = selection.cursor, let cell = visibleCells[cursor] else { return self }
            return cell
        }
        return element
    }

    /// VoiceOver's "show menu" (VO-Shift-M) on the list: the context menu of the selection.
    override open func accessibilityPerformShowMenu() -> Bool {
        showContextMenuForSelection()
    }

    /// Opens the context menu of the selected cell the keys are on — the one a right click on it
    /// would open — over that cell: for ⌃Return and VoiceOver's "show menu".
    @discardableResult
    public func showContextMenuForSelection() -> Bool {
        guard let cursor = selection.cursor else { return false }
        return showContextMenu(forCellAt: cursor)
    }

    /// The menu a right click on the cell would open, with the cell made part of the selection
    /// first in the same way, shown over the middle of the cell.
    private func showContextMenu(forCellAt index: Int) -> Bool {
        prepareSelection(forCellAt: index)
        guard let cell = visibleCells[index], let menu = delegate?.collectionView(self, menuForCellAt: index) else { return false }
        menu.allowsContextMenuPlugIns = false
        menu.popUp(positioning: nil, at: NSPoint(x: cell.bounds.midX, y: cell.bounds.midY), in: cell)
        return true
    }

    /// A cell outside the selection becomes the selection alone, as a right click makes it.
    private func prepareSelection(forCellAt index: Int) {
        if !selection.contains(index) {
            select(index, mode: .single, animated: true)
        }
    }

    private func index(of cell: CollectionViewCell) -> Int? {
        visibleCells.first { $0.value === cell }?.key
    }

    /// The cell's own actions, each run on the selection that includes the cell.
    func accessibilityCustomActions(for cell: CollectionViewCell) -> [NSAccessibilityCustomAction] {
        guard let index = index(of: cell), let delegate else { return [] }
        return delegate.collectionView(self, accessibilityActionsForCellAt: index).map { action in
            NSAccessibilityCustomAction(name: action.name) { [weak self, weak cell] in
                guard let self, let cell, let index = self.index(of: cell) else { return false }
                prepareSelection(forCellAt: index)
                return action.handler?() ?? false
            }
        }
    }

    /// Pressing a cell makes it the selection alone, as a double click does, and acts on it.
    func accessibilityPerformPress(on cell: CollectionViewCell) -> Bool {
        guard let index = index(of: cell), let delegate else { return false }
        select(index, mode: .single, animated: true)
        return delegate.collectionView(self, accessibilityPressCellAt: index)
    }

    func accessibilityPerformShowMenu(on cell: CollectionViewCell) -> Bool {
        guard let index = index(of: cell) else { return false }
        return showContextMenu(forCellAt: index)
    }

    /// The cell a focus notification is owed to: it was selected while off screen and is on its
    /// way into view.
    private var pendingAccessibilityFocusIndex: Int?

    /// Tells assistive apps that the selection moved, so VoiceOver reads the newly selected cell.
    private func announceSelectionForAccessibility() {
        NSAccessibility.post(element: self, notification: .selectedChildrenChanged)
        guard showsKeyboardFocus, let cursor = selection.cursor else {
            pendingAccessibilityFocusIndex = nil
            return
        }
        if let cell = visibleCells[cursor] {
            pendingAccessibilityFocusIndex = nil
            NSAccessibility.post(element: cell, notification: .focusedUIElementChanged)
        } else {
            pendingAccessibilityFocusIndex = cursor
        }
    }

    // MARK: - First responder

    /// The selection shows the accent colour while the keys come here: the collection is the
    /// first responder of the key window. Otherwise — the search field or a title being edited
    /// has the focus, or another window has the keyboard, such as the text of the preview's
    /// popover — it is grey.
    private var showsKeyboardFocus: Bool {
        isFirstResponder && window?.isKeyWindow == true
    }

    override open var acceptsFirstResponder: Bool { true }

    override open func becomeFirstResponder() -> Bool {
        isFirstResponder = true
        updateEmphasis()
        return true
    }

    override open func resignFirstResponder() -> Bool {
        isFirstResponder = false
        updateEmphasis()
        return true
    }

    override open func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        let center = NotificationCenter.default
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            if let window { center.removeObserver(self, name: name, object: window) }
            if let newWindow {
                center.addObserver(self, selector: #selector(windowKeyStateDidChange), name: name, object: newWindow)
            }
        }
    }

    override open func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEmphasis()
    }

    @objc private func windowKeyStateDidChange(_ notification: Notification) {
        updateEmphasis()
    }

    /// Told to the visible cells at once; how a cell shows it is the cell's affair (the item
    /// cards fade their selection ring).
    private func updateEmphasis() {
        let isEmphasized = showsKeyboardFocus
        for cell in visibleCells.values {
            cell.isEmphasized = isEmphasized
        }
    }

    // MARK: - Keyboard

    private enum Navigation {
        case next
        case previous
        case first
        case last
        case nextPage
        case previousPage
    }

    private func navigation(for event: NSEvent) -> Navigation? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let control = modifiers.contains(.control)
        let command = modifiers.contains(.command)
        let character = event.charactersIgnoringModifiers?.lowercased()

        switch event.keyCode {
        case KeyCode.rightArrow: return .next
        case KeyCode.leftArrow: return .previous
        case KeyCode.upArrow where command: return .first
        case KeyCode.downArrow where command: return .last
        // Home, End and the page keys, for keyboards and assistive apps that use them.
        case KeyCode.home: return .first
        case KeyCode.end: return .last
        case KeyCode.pageDown: return .nextPage
        case KeyCode.pageUp: return .previousPage
        default: break
        }
        // Emacs-style bindings.
        guard control else { return nil }
        switch character {
        case "f": return .next
        case "b": return .previous
        case "a": return .first
        case "e": return .last
        default: return nil
        }
    }

    override open func keyDown(with event: NSEvent) {
        guard let navigation = navigation(for: event) else {
            super.keyDown(with: event)
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let extending = modifiers.contains(.shift)

        switch navigation {
        case .next, .previous:
            // ⌘← and ⌘→ are left alone: they switch pinboards.
            if !extending, modifiers.contains(.command) {
                super.keyDown(with: event)
                return
            }
            guard let cursor = selection.cursor else { return }
            select(cursor + (navigation == .next ? 1 : -1), mode: extending ? .range : .single, animated: true)
        case .first:
            select(0, mode: extending ? .range : .single, animated: false)
        case .last:
            select(cellCount - 1, mode: extending ? .range : .single, animated: false)
        case .nextPage, .previousPage:
            guard let cursor = selection.cursor, cellCount > 0 else { return }
            let page = CollectionPaging.cellsPerPage(
                visibleWidth: scrollContainer.visibleDocumentRect.width,
                cellSide: contentLayout.cellSide,
                spacing: layoutConfiguration.interitemSpacing
            )
            let target = CollectionPaging.index(from: cursor, movingBy: navigation == .nextPage ? page : -page, cellCount: cellCount)
            select(target, mode: extending ? .range : .single, animated: true)
        }
    }

    override open func insertTab(_ sender: Any?) {
        if isFirstResponder { window?.selectNextKeyView(sender) }
    }

    override open func insertBacktab(_ sender: Any?) {
        if isFirstResponder { window?.selectPreviousKeyView(sender) }
    }

    // MARK: - Mouse

    private func cellIndex(at event: NSEvent) -> Int? {
        let point = scrollContainer.documentView.convert(event.locationInWindow, from: nil)
        return contentLayout.index(at: point).flatMap { visibleCells[$0] != nil ? $0 : nil }
    }

    override open func mouseDown(with event: NSEvent) {
        // Only a press on a cell can turn into a drag.
        initialDragLocation = nil
        guard let index = cellIndex(at: event), event.clickCount <= 2 else {
            super.mouseDown(with: event)
            return
        }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if modifiers.contains(.control) {
            rightMouseDown(with: event)
            return
        }

        if event.clickCount == 1 {
            initialDragLocation = convert(event.locationInWindow, from: nil)
            let mode: CollectionSelection.Mode = modifiers.contains(.shift) ? .range : modifiers.contains(.command) ? .toggle : .single
            if !selection.contains(index) || mode != .single {
                select(index, mode: mode, animated: true)
            } else {
                // Clicking inside a multiple selection may be the start of a drag: collapse
                // the selection only if the pointer stays put.
                dragWaitTimer?.invalidate()
                dragWaitTimer = Timer.scheduledTimer(withTimeInterval: Metrics.dragWaitInterval, repeats: false) { [weak self] _ in
                    MainActor.assumeIsolated {
                        self?.select(index, mode: .single, animated: true)
                    }
                }
            }
        } else {
            dragWaitTimer?.invalidate()
            dragWaitTimer = nil
            // A double click settles the selection on its cell quietly: no scrolling into view
            // and no selection hook, since the click is about to act on the cell.
            selection.select(index, mode: .single, cellCount: cellCount)
            refreshSelectionState()
        }
        delegate?.collectionView(self, didClickCellAt: index, with: event)
    }

    /// Any movement cancels the pending collapse of a multiple selection, so the selection
    /// survives being dragged; the drag itself starts once the pointer has travelled far enough.
    override open func mouseDragged(with event: NSEvent) {
        guard let start = initialDragLocation else { return }
        dragWaitTimer?.invalidate()
        dragWaitTimer = nil

        let location = convert(event.locationInWindow, from: nil)
        guard hypot(location.x - start.x, location.y - start.y) > DraggingMetrics.startDistance,
              !selection.isEmpty
        else { return }
        beginDraggingSelection(with: event)
        initialDragLocation = nil
    }

    /// Hook for subclasses; called as the pointer moves during a drag that started here, with
    /// its position on screen.
    open func draggingSessionDidMove(_ session: NSDraggingSession, to screenPoint: NSPoint) {}

    override open func rightMouseDown(with event: NSEvent) {
        guard let index = cellIndex(at: event), let cell = visibleCells[index] else {
            super.rightMouseDown(with: event)
            return
        }
        if !selection.contains(index) {
            select(index, mode: .single, animated: true)
        }
        if let menu = delegate?.collectionView(self, menuForCellAt: index) {
            // No entries from the system or other apps: the menu is exactly the card's own.
            menu.allowsContextMenuPlugIns = false
            NSMenu.popUpContextMenu(menu, with: event, for: cell)
        }
    }
}
