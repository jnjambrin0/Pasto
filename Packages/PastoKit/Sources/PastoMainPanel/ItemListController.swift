import AppKit
import os
import PastoCore
import PastoCoreUI
import PastoFoundation
import PastoUI

/// Feeds the item strip from the store: it shows one list (the clipboard history or a
/// pinboard), keeps the strip in step with it, and carries out what the user does with the
/// items — with keys, the context menu and drags.
///
/// What changes the store it does itself, through the undoable writer. What needs the rest of
/// the app — pasting, copying, and the features that live in other modules — it asks for
/// through the callbacks; one that is left unset takes its menu entry away.
public final class ItemListController {
    /// The user chose items to paste: Return, Enter, a double click, ⌘V, a quick-paste shortcut
    /// or the menu.
    public var onPaste: ((_ ids: [ItemID], _ plainText: Bool, _ forcesDirectPaste: Bool) -> Void)?
    /// ⌘C on the selection, or "Copy" in the menu.
    public var onCopy: ((_ ids: [ItemID], _ plainText: Bool) -> Void)?
    /// "Edit": open an editor for each of these items.
    public var onEdit: (([ItemID]) -> Void)?
    /// Writing Tools: open an editor for each of these text items and start Writing Tools in it.
    public var onWritingTools: (([ItemID]) -> Void)?
    /// "Preview" or Space: show the item's preview, or close it if it is the one on show.
    public var onPreview: ((ItemID) -> Void)?
    /// The item selected last is another one — moved to with the keys or the mouse, or selected
    /// because the content changed under the selection. Reported with its card once the strip
    /// has finished bringing the card into view, at once if part of it was showing; several
    /// changes in one turn are reported once, and without a card there is a beep and no report.
    /// An open preview follows it. A capture that selects the new item reports at once and with
    /// no card: the open preview shows the new item where it was, over the card it had, which
    /// the new one has pushed along.
    public var onSelectedItemChange: ((_ item: ItemID, _ card: NSView?) -> Void)?
    /// "Create Stack": make a Paste Stack of these items, or add them to the one there is.
    public var onCreateStack: (([ItemID]) -> Void)?
    /// Whether the Paste Stack is on screen, in which case the menu does not offer to create one.
    public var isPasteStackVisible: () -> Bool = { false }
    /// "Show in …" or ⌘G on a search result: leaving the results for that list is the search's
    /// business, which then asks for the list and for `reveal(_:)`.
    public var onShowSearchResultInList: ((_ item: ItemID, _ list: ListID) -> Void)?
    /// "Show in …": show this list. The controller then selects the item in it.
    public var onShowInList: ((ListID) -> Void)?
    /// "Show in …" or ⌘G on a suggestion: leaving the suggestions is their mode's business,
    /// which then asks for the list.
    var onShowPickInList: ((_ item: ItemID, _ list: ListID) -> Void)?
    /// What dragging these items out carries for other applications, by item
    /// (`ItemRestorer.draggingContents`). Unset, cards can only be dragged inside the panel.
    public var draggingContents: ((_ ids: [ItemID], _ options: RestoreOptions) -> [ItemID: [PasteboardItemSnapshot]])?

    /// Services and settings the cards share. Setting it refreshes the cards on show.
    public var cellEnvironment: ItemCellEnvironment {
        didSet { reconfigureVisibleCells() }
    }

    let reader: StoreReader
    let writer: UndoableWriter
    let config: ConfigStore
    let collectionView: ItemCollectionView
    let log = Log.logger(.panel)
    /// The cards' decoded content, so that scrolling back and reconfiguring do not decode it again.
    private let contentCache = ItemCellContentCache()
    private(set) var list: ListID
    private var itemCollection: ItemCollection
    /// The history's collection, once it has been shown, for as long as the controller lives:
    /// creating it reads the whole history (150 ms or more with a year of it), and it keeps
    /// itself current in the background while another list is on show.
    private var historyCollection: ItemCollection?
    /// The search results on show instead of the list; nil while the strip shows the list.
    private var searchResults: [ItemID]?
    /// The suggestions on show instead of the list; nil while there are none. Search results
    /// take precedence.
    private var picks: [ItemID]?
    private var applier = SnapshotApplier<ItemID>()
    /// The newest snapshot not yet shown; snapshots arriving in one turn are applied as one change.
    private var pendingSnapshot: CollectionSnapshot<ItemID>?
    private var isApplicationScheduled = false
    /// The item that takes the selection once the strip shows a deletion that has been saved.
    private var pendingNeighborID: ItemID?
    /// A captured item to select as soon as the strip shows it in first place.
    private var pendingNewestItemID: ItemID?
    /// The item to select when the strip next shows that list ("Show in …"), and how far from
    /// the leading edge of the strip its card was; nil if it was not on screen.
    var pendingFocus: (itemID: ItemID, list: ListID, leadingOffset: CGFloat?)?
    /// The item selected last as `onSelectedItemChange` last reported it.
    private var reportedSelectedItemID: ItemID?
    private var isSelectionReportScheduled = false
    /// The selection about to be reported came from a capture, not from the user.
    private var isReportingCapturedSelection = false

    public init(
        reader: StoreReader,
        writer: UndoableWriter,
        config: ConfigStore,
        collectionView: ItemCollectionView,
        cellEnvironment: ItemCellEnvironment,
        list: ListID = .clipboard
    ) {
        self.reader = reader
        self.writer = writer
        self.config = config
        self.cellEnvironment = cellEnvironment
        self.collectionView = collectionView
        self.list = list
        itemCollection = reader.itemCollection(for: list)
        if list == .clipboard {
            historyCollection = itemCollection
        }

        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.onCommand = { [weak self] in self?.perform($0) }
        collectionView.onSelectionChange = { [weak self] in self?.scheduleSelectionReport() }
        collectionView.isReorderingEnabled = Self.canReorder(list)
        observe(itemCollection)
        updateAccessibilityLabel()
    }

    /// VoiceOver names the strip after the list it shows: "Clipboard" or the pinboard's name.
    private func updateAccessibilityLabel() {
        collectionView.setAccessibilityLabel(reader.list(list).map { TabBarItem(list: $0).name })
    }

    /// Switches the strip to another list.
    public func show(_ list: ListID) {
        self.list = list
        updateAccessibilityLabel()
        // Search results and suggestions stay on top of whatever list is chosen under them.
        guard searchResults == nil, picks == nil else { return }
        replaceCollection(with: collection(for: list))
        applier = SnapshotApplier()
        pendingNeighborID = nil
        pendingNewestItemID = nil
        collectionView.isReorderingEnabled = Self.canReorder(list)
        observe(itemCollection)
        focusPendingItem()
    }

    /// Shows search results in place of the list, or goes back to the list with nil. The results
    /// are live: they follow the store as a list does, without ever taking in other items. The
    /// first ones and the return to the list are a fresh start; after that every change goes
    /// through the applier without animation.
    var isShowingSearchResults: Bool { searchResults != nil }

    public func showSearchResults(_ ids: [ItemID]?) {
        let wasSearching = searchResults != nil
        searchResults = ids
        guard let ids else {
            if wasSearching { show(list) }
            return
        }
        // The item that was to take the selection after a deletion belongs to the results it
        // was chosen in; the results of another query select as they come.
        pendingNeighborID = nil
        if !wasSearching {
            applier = SnapshotApplier()
            pendingNewestItemID = nil
            // Results have no order of the user's own, whatever list is under them.
            collectionView.isReorderingEnabled = false
        }
        replaceCollection(with: reader.itemCollection(among: ids))
        observe(itemCollection)
    }

    /// The live collection of `list`: the history's is made once and kept.
    private func collection(for list: ListID) -> ItemCollection {
        guard list == .clipboard else { return reader.itemCollection(for: list) }
        if let historyCollection {
            return historyCollection
        }
        let collection = reader.itemCollection(for: .clipboard)
        historyCollection = collection
        return collection
    }

    /// Stops following the collection on show, which may live on (the history's), and makes
    /// `collection` the one on show; `observe(_:)` then follows it.
    private func replaceCollection(with collection: ItemCollection) {
        itemCollection.onChange = nil
        itemCollection = collection
    }

    /// Whether the strip shows suggestions.
    var isShowingPicks: Bool { picks != nil }

    /// Shows suggestions in place of the list, or goes back to the list with nil. They are a
    /// fixed list in the order given — the ranking's — which the caller replaces when it
    /// changes. Like search results they have no order of the user's own and change without
    /// animation.
    public func showPicks(_ ids: [ItemID]?) {
        let wasShowingPicks = picks != nil
        picks = ids
        guard searchResults == nil else { return }
        guard let ids else {
            if wasShowingPicks { show(list) }
            return
        }
        if !wasShowingPicks {
            // The list under the suggestions is no longer followed.
            itemCollection.onChange = nil
            applier = SnapshotApplier()
            pendingNeighborID = nil
            pendingNewestItemID = nil
            collectionView.isReorderingEnabled = false
        }
        pendingSnapshot = CollectionSnapshot(ids: ids)
        flush()
    }

    /// The card showing an item, once it is fully in view; nil if the strip does not hold it.
    /// Scrolls the strip, with animation, until the card of `id` is in view and hands it over;
    /// `nil` when the item is not in the list or another scroll took over on the way.
    public func bringCellIntoView(for id: ItemID, completion: @escaping (NSView?) -> Void) {
        guard let index = index(of: id) else { return completion(nil) }
        collectionView.scrollToCell(at: index, animated: true) { [weak self] finished in
            guard finished, let self, let index = self.index(of: id) else { return completion(nil) }
            collectionView.layoutSubtreeIfNeeded()
            completion(collectionView.cell(at: index))
        }
    }

    public func visibleCell(for id: ItemID) -> NSView? {
        guard let index = index(of: id) else { return nil }
        collectionView.scrollToCell(at: index, animated: false)
        collectionView.layoutSubtreeIfNeeded()
        return collectionView.cell(at: index)
    }

    /// Selects `id` in the list on show — at once, or as soon as search results on top of it
    /// give way — with its card where it is on screen now.
    public func reveal(_ id: ItemID) {
        focus(id, onceShowing: list)
    }

    /// Remembers to select `id` once the strip shows `list`, and where its card is on screen.
    func focus(_ id: ItemID, onceShowing list: ListID) {
        let leadingOffset = index(of: id).flatMap(collectionView.leadingOffset(ofCellAt:))
        pendingFocus = (id, list, leadingOffset)
        focusPendingItem()
    }

    /// A capture gave the history a new newest item. A strip showing the history moves its
    /// selection to it, whether the panel is open or closed.
    public func didCaptureNewestItem(_ id: ItemID) {
        guard list == .clipboard, searchResults == nil, picks == nil else { return }
        flush()
        // The store's change usually precedes this notice, but nothing guarantees it.
        pendingNewestItemID = id
        selectPendingNewestItem()
    }

    /// Only a pinboard has an order of the user's own.
    private static func canReorder(_ list: ListID) -> Bool {
        list != .clipboard
    }

    // MARK: - What is shown and selected

    /// The selected items, in the order they were selected.
    public var selectedItemIDs: [ItemID] {
        collectionView.selection.indexes.compactMap(itemID(at:))
    }

    var selectedItems: [Item] {
        reader.items(selectedItemIDs)
    }

    func itemID(at index: Int) -> ItemID? {
        applier.ids.indices.contains(index) ? applier.ids[index] : nil
    }

    func index(of id: ItemID) -> Int? {
        applier.ids.firstIndex(of: id)
    }

    /// The item that inherits the selection when the selected ones are deleted: the one right
    /// after them or, at the end of the list, the one right before.
    func neighborOfSelection() -> ItemID? {
        let selected = collectionView.selection.indexes
        guard let highest = selected.max(), let lowest = selected.min() else { return nil }
        return [highest + 1, lowest - 1]
            .first { !selected.contains($0) && itemID(at: $0) != nil }
            .flatMap(itemID(at:))
    }

    /// The selection changes inside `select` before the strip scrolls to it: the report waits
    /// for the next turn, when the scroll to the card has started.
    private func scheduleSelectionReport() {
        guard onSelectedItemChange != nil, !isSelectionReportScheduled else { return }
        isSelectionReportScheduled = true
        DispatchQueue.main.async { [weak self] in self?.reportSelectedItem() }
    }

    /// Waits for the strip to finish scrolling to the card — no wait when part of it was already
    /// showing — and reports the item with its card; with no card to show it over, it beeps
    /// instead. A later selection, or another scroll that takes over, leaves the report to
    /// whatever comes next.
    private func reportSelectedItem() {
        isSelectionReportScheduled = false
        let isCaptured = isReportingCapturedSelection
        isReportingCapturedSelection = false
        let id = selectedItemIDs.last
        guard id != reportedSelectedItemID else { return }
        reportedSelectedItemID = id
        guard let id else { return }
        guard !isCaptured else {
            onSelectedItemChange?(id, nil)
            return
        }
        collectionView.whenSelectionScrollEnds { [weak self] finished in
            guard finished, let self, selectedItemIDs.last == id else { return }
            collectionView.layoutSubtreeIfNeeded()
            guard let card = index(of: id).flatMap(collectionView.cell(at:)) else {
                // Not while the panel is away: nothing is on screen to answer for.
                if collectionView.window?.isVisible == true { NSSound.beep() }
                return
            }
            onSelectedItemChange?(id, card)
        }
    }

    func requestPaste(_ request: ItemCollectionView.PasteRequest) {
        let ids: [ItemID]
        if let index = request.quickPasteIndex {
            // Quick paste addresses the item by its position in the list, whatever is selected.
            ids = itemID(at: index).map { [$0] } ?? []
        } else {
            ids = selectedItemIDs
        }
        if !ids.isEmpty { onPaste?(ids, request.plainText, request.forcesDirectPaste) }
    }

    // MARK: - Applying snapshots

    private func observe(_ collection: ItemCollection) {
        collection.onChange = { [weak self] in self?.schedule($0) }
        pendingSnapshot = collection.snapshot
        flush()
    }

    /// Shows `snapshot` on the next turn of the main queue, so that a burst of store changes
    /// becomes a single transition.
    private func schedule(_ snapshot: CollectionSnapshot<ItemID>) {
        pendingSnapshot = snapshot
        guard !isApplicationScheduled else { return }
        isApplicationScheduled = true
        DispatchQueue.main.async { [weak self] in self?.flush() }
    }

    private func flush() {
        isApplicationScheduled = false
        while let snapshot = pendingSnapshot {
            pendingSnapshot = nil
            apply(snapshot)
        }
        collectionView.contentDidChange(showing: shownCollection)
    }

    /// The kind of list the strip is showing.
    public var shownCollection: ItemCellContext.Collection {
        searchResults != nil ? .search : picks != nil ? .picks : list == .clipboard ? .history : .pinboard
    }

    private func apply(_ snapshot: CollectionSnapshot<ItemID>) {
        switch applier.apply(snapshot) {
        case .none:
            return
        case .reload:
            collectionView.reloadData()
        case .changes(let changeset):
            // Changes made while the panel is closed are simply there when it opens. Search
            // results and suggestions change without animation: refining a query or a late
            // reranking is not a transition.
            collectionView.apply(changeset, animated: collectionView.window?.isVisible == true && searchResults == nil && picks == nil)
        }
        contentDidChange()
    }

    /// Runs after every change of content that the strip has taken in.
    private func contentDidChange() {
        // The cards that stayed may have changed position, and with it their quick paste number.
        for (index, cell) in collectionView.visibleCellsByIndex {
            (cell as? ItemCell)?.quickPasteIndex = ItemCellModel.quickPasteIndex(forCellAt: index)
        }
        if let id = pendingNeighborID {
            pendingNeighborID = nil
            if let index = index(of: id) {
                collectionView.select(index, animated: false)
            }
        }
        selectPendingNewestItem()
    }

    private func selectPendingNewestItem() {
        guard let id = pendingNewestItemID, applier.ids.first == id else { return }
        pendingNewestItemID = nil
        isReportingCapturedSelection = true
        collectionView.select(0, animated: true)
        // Nothing to report when the item was already the selection.
        if !isSelectionReportScheduled { isReportingCapturedSelection = false }
    }

    /// Selects the item "Show in …" asked for, once the strip shows the list it is in, and puts
    /// its card where it was on screen — or, if it was not on screen, simply brings it into view.
    private func focusPendingItem() {
        guard let focus = pendingFocus, focus.list == list, searchResults == nil, picks == nil else { return }
        pendingFocus = nil
        guard let index = index(of: focus.itemID) else { return }
        collectionView.select(index, animated: false)
        if let leadingOffset = focus.leadingOffset {
            collectionView.scrollToCell(at: index, leadingOffset: leadingOffset)
        } else {
            collectionView.scrollToCell(at: index, animated: false)
        }
    }

    /// Selects `id` once the strip no longer shows any of `deleted` — now, if it has already
    /// taken the deletion in.
    func select(_ id: ItemID, onceTheStripLeavesOut deleted: [ItemID]) {
        if deleted.contains(where: { index(of: $0) != nil }) {
            pendingNeighborID = id
        } else if let index = index(of: id) {
            collectionView.select(index, animated: false)
        }
    }

    private func reconfigureVisibleCells() {
        for (index, cell) in collectionView.visibleCellsByIndex {
            guard let cell = cell as? ItemCell, let model = cellModel(at: index) else { continue }
            configure(cell, with: model)
        }
    }
}

extension ItemListController: CollectionViewDataSource {
    public func numberOfCells(in collectionView: CollectionView) -> Int {
        applier.ids.count
    }

    public func collectionView(_ collectionView: CollectionView, cellAt index: Int) -> CollectionViewCell {
        guard let model = cellModel(at: index) else {
            // The item vanished between the snapshot and now; the next snapshot removes its cell.
            return ItemCellFactory.dequeueCell(for: .unknown, from: collectionView)
        }
        let cell = ItemCellFactory.dequeueCell(for: model.type, from: collectionView)
        configure(cell, with: model)
        return cell
    }

    public func collectionView(_ collectionView: CollectionView, reconfigure cell: CollectionViewCell, at index: Int) {
        guard let cell = cell as? ItemCell, let model = cellModel(at: index) else { return }
        configure(cell, with: model)
    }

    /// Built in the strip's appearance whichever path asks for it: a text's colours can be
    /// dynamic, and the model resolves them (`TextCardBackground.Summary`). The content is
    /// decoded once per preview and appearance (`ItemCellContentCache`).
    private func cellModel(at index: Int) -> ItemCellModel? {
        guard let item = itemID(at: index).flatMap(reader.item) else { return nil }
        let context = ItemCellContext(
            collection: shownCollection,
            pinboard: item.listID.flatMap(reader.list),
            quickPasteIndex: ItemCellModel.quickPasteIndex(forCellAt: index)
        )
        let appearance = collectionView.effectiveAppearance
        let content = contentCache.content(for: item.preview, in: appearance.name) {
            var content = ItemCellModel.Content.unknown
            appearance.performAsCurrentDrawingAppearance {
                content = ItemCellModel.Content(item.preview)
            }
            return content
        }
        return ItemCellModel(item: item, context: context, content: content)
    }

    private func configure(_ cell: ItemCell, with model: ItemCellModel) {
        cell.configure(with: model, sizeClass: collectionView.sizeClass, environment: cellEnvironment)
        let id = model.id
        cell.onRename = { [weak self] title in self?.rename(id, to: title) }
    }
}
