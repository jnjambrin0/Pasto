import AppKit
import os
import PastoCore
import PastoCoreUI
import PastoFoundation
import PastoUI

// What the user does with the items of the strip. Keys and menu entries end in the same
// functions.

// MARK: - Keys

extension ItemListController {
    func perform(_ command: ItemCollectionView.Command) {
        switch command {
        case .paste(let request):
            requestPaste(request)
        case .copy(let plainText):
            onCopy?(selectedItemIDs, plainText)
        case .delete:
            deleteSelection()
        case .open:
            openSelection()
        case .rename:
            // The item selected last, like every action on "the" item of a multiple selection.
            if let id = selectedItemIDs.last { beginRenaming(id) }
        case .edit:
            editSelection()
        case .writingTools:
            startWritingToolsOnSelection()
        case .showInList:
            // The first list "Show in …" offers, in the strip and over search results alike.
            if let list = showInLists.first, let id = selectedItemIDs.first { show(id, in: list) }
        case .createStack:
            createStackOfSelection()
        case .preview:
            if let id = selectedItemIDs.last { onPreview?(id) }
        }
    }
}

// MARK: - Context menu

extension ItemListController {
    /// The menu of the card at `index`. Which entries it has depends on that card alone; what
    /// most of them act on is the selection, read when the entry is chosen.
    func makeContextMenu(forItemAt index: Int) -> NSMenu? {
        guard let item = itemID(at: index).flatMap(reader.item) else { return nil }
        let writingToolsItem = NSMenuItem.writingToolsItems.first

        var content = ItemMenuContent()
        content.canOpen = ItemExternalActions.openableURL(of: item) != nil
        content.openingApplicationName = ItemExternalActions.openingApplicationName(for: item)
        content.isFiles = item.type == .files
        content.showInLists = showInLists
        content.pasteTargetName = NSWorkspace.shared.menuBarOwningApplication?.localizedName
        content.isAlwaysPlainText = config.value(for: .isPasteAsPlainTextEnabled)
        content.offersShowIn = onShowInList != nil
        content.offersCreateStack = onCreateStack != nil && !isPasteStackVisible()
        content.offersEdit = onEdit != nil && item.type.hasEditableContent
        content.offersWritingTools = content.offersEdit && onWritingTools != nil
            && item.type == .text && writingToolsItem != nil
        content.offersPreview = onPreview != nil

        let itemID = item.id
        return ItemContextMenu.make(entries: content.entries, configuration: ItemContextMenu.Configuration(
            plainTextModifierFlags: collectionView.plainTextModifierFlags,
            createStackKeyEquivalent: collectionView.createStackKeyEquivalent,
            listName: { [reader] in reader.list($0).map(TabBarItem.init(list:))?.name },
            listSymbol: { [reader] in Self.symbolName(for: reader.list($0)) },
            pinSubmenu: makePinMenu(),
            // Only the clicked item is shared, whatever else is selected.
            shareItem: ShareMenu.item { [reader] in
                ItemExternalActions.shareableItems(of: item, pasteboardItems: reader.pasteboardItems(for: itemID) ?? [])
            },
            writingToolsItem: writingToolsItem,
            perform: { [weak self] in self?.perform($0, onItem: itemID) }
        ))
    }

    private static func symbolName(for list: ClipList?) -> String {
        switch list?.type {
        case .pinboard: list?.isShared == true ? "circlebadge.2" : "circlebadge"
        case .clipboard, nil: "clock.arrow.circlepath"
        }
    }

    /// - Parameter clicked: The item whose card the menu was opened on.
    func perform(_ entry: ItemMenuEntry, onItem clicked: ItemID) {
        switch entry {
        case .open:
            openSelection()
        case .revealInFinder:
            if !ItemExternalActions.revealInFinder(selectedItems) { NSSound.beep() }
        case .showIn(let list):
            show(clicked, in: list)
        case .paste:
            // With "always paste as plain text" on, the menu's one paste entry is fully
            // plain: images, colours and files go as their text too, which Return does not do.
            let plainText = config.value(for: .isPasteAsPlainTextEnabled)
            requestPaste(ItemCollectionView.PasteRequest(plainText: plainText))
        case .pasteAsPlainText:
            requestPaste(ItemCollectionView.PasteRequest(plainText: true))
        case .copy:
            onCopy?(selectedItemIDs, false)
        case .createStack:
            createStackOfSelection()
        case .edit:
            onEdit?([clicked])
        case .writingTools:
            onWritingTools?([clicked])
        case .rename:
            beginRenaming(clicked)
        case .delete:
            deleteSelection()
        case .preview:
            onPreview?(clicked)
        case .pin, .share, .separator:
            // Submenus and separators have nothing to run.
            break
        }
    }

    /// The pin menu for one item, whatever is selected: what its preview offers.
    public func pinMenu(for id: ItemID) -> NSMenu? {
        reader.item(id).map { makePinMenu(for: [$0]) }
    }

    /// What sharing one item hands to the system, shown as a picker next to `anchor`.
    public func showSharingPicker(for id: ItemID, anchoredTo anchor: NSView) {
        guard let item = reader.item(id) else { return }
        let shared = ItemExternalActions.shareableItems(of: item, pasteboardItems: reader.pasteboardItems(for: id) ?? [])
        NSSharingServicePicker(items: shared).show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
    }

    /// The submenu acts on the selection as it is when the menu opens.
    func makePinMenu() -> NSMenu {
        makePinMenu(for: selectedItems)
    }

    private func makePinMenu(for selection: [Item]) -> NSMenu {
        let ids = selection.map(\.id)
        // Only the history offers it, where every item stays after being unpinned. Inside a
        // pinboard the way to take an item off it is to delete it there; among search results
        // and suggestions an item may live on its pinboard alone.
        let canUnpin = shownCollection == .history && selection.contains { $0.listID != nil }

        return PinMenu.make(
            selection: selection,
            pinboards: reader.lists().filter { $0.type == .pinboard },
            actions: PinMenu.Actions(
                pin: { [weak self] pinboard in
                    self?.write { try $0.pin(ids, to: pinboard) }
                },
                createPinboardAndPin: { [weak self] in
                    let name = TabBarItem.untitledPinboardName
                    let color = PinboardColor.allCases.randomElement() ?? .blue
                    self?.write { context in
                        try context.pin(ids, to: try context.createPinboard(name: name, color: color))
                    }
                },
                unpin: canUnpin ? { [weak self] in self?.write { try $0.unpin(ids) } } : nil
            )
        )
    }
}

// MARK: - Actions

extension ItemListController {
    /// Deleting takes the selection out of the list on show and nowhere else; an item that is
    /// in no other list is gone for good. Search results are not in a list: deleting one deletes
    /// it from everywhere. Suggestions come from the history, and leave it. One item goes
    /// without asking; two or more ask first.
    private func deleteSelection() {
        let ids = selectedItemIDs
        guard !ids.isEmpty else {
            NSSound.beep()
            return
        }
        let neighbor = neighborOfSelection()
        if ids.count >= 2 {
            let confirmed = PanelAlert.confirm(title: ItemActionStrings.deleteItemsTitle(ids.count), action: ItemActionStrings.delete)
            guard confirmed else { return }
        }
        let list: ListID? = switch shownCollection {
        case .search: nil
        case .picks: .clipboard
        case .history, .pinboard: list
        }
        write({ context in
            if let list {
                try context.remove(ids, from: list)
            } else {
                try context.delete(ids)
            }
        }, then: { [weak self] in
            if let neighbor { self?.select(neighbor, onceTheStripLeavesOut: ids) }
        })
    }

    private func openSelection() {
        if !ItemExternalActions.open(selectedItems) { NSSound.beep() }
    }

    /// Renaming is done on one card, which becomes the whole selection. A card that is
    /// scrolled out of view cannot be renamed.
    private func beginRenaming(_ id: ItemID) {
        guard let index = index(of: id), let cell = collectionView.cell(at: index) as? ItemCell else { return }
        collectionView.select(index, mode: .single, animated: true)
        cell.beginTitleEditing()
    }

    func rename(_ id: ItemID, to title: String?) {
        write { try $0.setTitle(title, of: id) }
    }

    private func editSelection() {
        guard let onEdit else { return }
        let editable = selectedItems.filter(\.type.hasEditableContent).map(\.id)
        guard !editable.isEmpty else {
            NSSound.beep()
            return
        }
        onEdit(editable)
    }

    private func startWritingToolsOnSelection() {
        guard let onWritingTools, !NSMenuItem.writingToolsItems.isEmpty else { return }
        let texts = selectedItems.filter { $0.type == .text }.map(\.id)
        if !texts.isEmpty { onWritingTools(texts) }
    }

    /// The stack takes the selected items in the order the strip shows them, whatever order they
    /// were selected in.
    private func createStackOfSelection() {
        guard let onCreateStack else { return }
        let ids = collectionView.selection.indexes.sorted().compactMap(itemID(at:))
        guard !ids.isEmpty else {
            NSSound.beep()
            return
        }
        onCreateStack(ids)
    }

    /// The other lists the selected item is in. Search results and suggestions are in no list of
    /// their own, so all of the item's are offered.
    private var showInLists: [ListID] {
        let shownList: ListID? = isShowingSearchResults || isShowingPicks ? nil : list
        return ShowInLists.lists(for: selectedItems, shownList: shownList)
    }

    /// Asks for `list` to be shown with the item selected in it. Over search results the search
    /// leaves them first.
    private func show(_ id: ItemID, in list: ListID) {
        if isShowingSearchResults {
            onShowSearchResultInList?(id, list)
        } else if isShowingPicks {
            onShowPickInList?(id, list)
        } else if let onShowInList {
            focus(id, onceShowing: list)
            onShowInList(list)
        }
    }

    /// Changes the store as the user, as one step of undo; `completion` runs once the change is
    /// saved, and not if it fails.
    func write(_ change: @escaping @Sendable (WritingContext) throws -> Void, then completion: (() -> Void)? = nil) {
        Task { [writer, log] in
            do {
                try await writer.perform(change)
                completion?()
            } catch {
                log.error("Changing items failed: \(error)")
            }
        }
    }
}

// MARK: - Clicks, menu and drags

extension ItemListController: CollectionViewDelegate {
    public func collectionView(_ collectionView: CollectionView, didClickCellAt index: Int, with event: NSEvent) {
        guard event.clickCount == 2 else { return }
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let plainText = modifiers.isSuperset(of: self.collectionView.plainTextModifierFlags)
        requestPaste(ItemCollectionView.PasteRequest(plainText: plainText))
    }

    public func collectionView(_ collectionView: CollectionView, menuForCellAt index: Int) -> NSMenu? {
        makeContextMenu(forItemAt: index)
    }

    /// Every card carries what a paste of it would write — as plain text if the plain-text
    /// modifier is held when the drag starts — and its identifier. A card with nothing to give
    /// other applications still carries the identifier, so it can be dragged inside the panel.
    public func collectionView(_ collectionView: CollectionView, pasteboardWritersForCellsAt indexes: [Int]) -> [[any NSPasteboardWriting]] {
        let ids = indexes.compactMap(itemID(at:))
        let modifiers = NSEvent.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let options: RestoreOptions = modifiers.isSuperset(of: self.collectionView.plainTextModifierFlags) ? .plainText : []
        let contents = draggingContents?(ids, options) ?? [:]

        return indexes.map { index in
            guard let id = itemID(at: index) else { return [] }
            let elements = contents[id] ?? []
            return elements.isEmpty
                ? [ItemPasteboardWriter(itemID: id, content: nil)]
                : elements.map { ItemPasteboardWriter(itemID: id, content: $0) }
        }
    }

    public func collectionView(_ collectionView: CollectionView, moveCellsAt indexes: [Int], to destination: Int) {
        // Positions among search results or suggestions are not positions on the pinboard.
        guard shownCollection == .pinboard else { return }
        let ids = indexes.compactMap(itemID(at:))
        let list = list
        write { try $0.moveItems(ids, toIndex: destination, in: list) }
    }
}
