import AppKit
import os
import PastoCore
import PastoFoundation

extension ConfigKey where Value == String {
    /// The list the panel shows. Empty, or naming a list that no longer exists, means the
    /// clipboard history.
    public static var selectedListIdentifier: ConfigKey<String> {
        ConfigKey("selectedListIdentifier", default: "")
    }
}

/// Keeps the toolbar's tabs in step with the user's lists and carries out what the user does
/// with them: choosing the list the panel shows, and creating, renaming, recolouring,
/// reordering and deleting pinboards.
public final class ListTabsController {
    /// The list the panel shows changed.
    public var onSelect: ((ListID) -> Void)?
    /// The user erased the history and the erasure is saved: whatever was learnt from it goes
    /// too (the suggestions' journals).
    public var onEraseHistory: (() -> Void)?

    public private(set) var selectedList: ListID

    /// How long after "+" creates a pinboard its tab starts being renamed.
    private static let renameDelay = Duration.milliseconds(200)

    private let reader: StoreReader
    private let writer: StoreWriter
    /// Writes what the user does to items: dropping them on a tab, which can be undone, and
    /// deleting a pinboard or erasing the history, which cannot and clears what could.
    private let itemWriter: UndoableWriter
    private let config: ConfigStore
    private let toolbar: Toolbar
    private let lists: ListCollection
    /// A pinboard that was just created, to rename as soon as its tab exists.
    private var pinboardToRename: ListID?
    private let log = Log.logger(.panel)

    public init(reader: StoreReader, writer: StoreWriter, itemWriter: UndoableWriter, config: ConfigStore, toolbar: Toolbar) {
        self.reader = reader
        self.writer = writer
        self.itemWriter = itemWriter
        self.config = config
        self.toolbar = toolbar
        lists = reader.listCollection()

        let remembered = ListID(rawValue: config.value(for: .selectedListIdentifier))
        selectedList = reader.list(remembered) != nil ? remembered : .clipboard

        let tabBar = toolbar.tabBar
        tabBar.setItems(tabs, animated: false)
        tabBar.select(selectedList, animated: false)

        lists.onChange = { [weak self] _ in self?.listsDidChange() }
        tabBar.onSelect = { [weak self] in self?.didSelect($0) }
        tabBar.onRename = { [weak self] id, name in
            self?.write { try $0.renameList(id, to: name) }
        }
        tabBar.onReorder = { [weak self] ids in
            self?.write { try $0.reorderLists(ids) }
        }
        tabBar.onDropItems = { [weak self] ids, list in self?.drop(ids, on: list) }
        toolbar.onCreatePinboard = { [weak self] in self?.createPinboard() }
        toolbar.tabMenuActions = self
        toolbar.itemCount = { [reader] in reader.itemCount(in: $0) }
    }

    /// Shows another list, as if the user had chosen its tab.
    public func select(_ id: ListID) {
        guard id != selectedList, reader.list(id) != nil else { return }
        toolbar.tabBar.select(id, animated: true)
        didSelect(id)
    }

    private var tabs: [TabBarItem] {
        reader.lists().map(TabBarItem.init(list:))
    }

    private func didSelect(_ id: ListID) {
        selectedList = id
        config.set(id.rawValue, for: .selectedListIdentifier)
        onSelect?(id)
    }

    private func listsDidChange() {
        let previousOrder = toolbar.tabBar.items.map(\.id)
        let tabs = self.tabs
        toolbar.tabBar.setItems(tabs, animated: true)
        // The pinboard on show was deleted, here or on another device: the tab that takes its
        // place is shown — the next one or, if it was the last, the one before.
        if reader.list(selectedList) == nil {
            let successor = TabSuccession.successor(
                of: selectedList, in: previousOrder, remaining: Set(tabs.map(\.id))
            ) ?? .clipboard
            toolbar.tabBar.select(successor, animated: true)
            didSelect(successor)
        }
        if let id = pinboardToRename, reader.list(id) != nil {
            pinboardToRename = nil
            toolbar.tabBar.beginRenaming(id)
        }
    }

    // MARK: - Pinboards

    /// "+" creates the pinboard at once, with a placeholder name and a colour drawn at random
    /// from the eight, and a moment later puts its tab in rename mode. The new tab is not
    /// selected, and cancelling the rename keeps the pinboard.
    private func createPinboard() {
        let name = TabBarItem.untitledPinboardName
        let color = PinboardColor.allCases.randomElement() ?? .blue
        Task { [weak self, writer, log] in
            let id: ListID
            do {
                id = try await writer.perform(author: .user) { try $0.createPinboard(name: name, color: color) }
            } catch {
                log.error("Creating a pinboard failed: \(error)")
                return
            }
            try? await Task.sleep(for: Self.renameDelay)
            self?.beginRenamingOnceShown(id)
        }
    }

    /// The store's change notice and the end of the write arrive in no particular order.
    private func beginRenamingOnceShown(_ id: ListID) {
        if toolbar.tabBar.items.contains(where: { $0.id == id }) {
            toolbar.tabBar.beginRenaming(id)
        } else {
            pinboardToRename = id
        }
    }

    /// An empty pinboard goes without asking; one with items asks first.
    private func deletePinboard(_ id: ListID) {
        guard let list = reader.list(id) else { return }
        if reader.itemCount(in: id) > 0 {
            let confirmed = PanelAlert.confirm(
                title: ToolbarStrings.deletePinboardTitle(TabBarItem(list: list).name),
                message: ToolbarStrings.deletePinboardMessage,
                action: ToolbarStrings.delete
            )
            guard confirmed else { return }
        }
        writeIrreversibly { try $0.deleteList(id) }
    }

    /// An empty history is erased without asking.
    private func eraseHistory() {
        if reader.itemCount(in: .clipboard) > 0 {
            let confirmed = PanelAlert.confirm(
                title: ToolbarStrings.eraseHistoryTitle,
                message: ToolbarStrings.eraseHistoryMessage,
                action: ToolbarStrings.erase
            )
            guard confirmed else { return }
        }
        writeIrreversibly({ _ = try $0.eraseHistory() }, then: { [weak self] in self?.onEraseHistory?() })
    }

    /// Cards dropped on a pinboard's tab are pinned to it, exactly as the "Pin" menu does;
    /// dropped on the history's tab, they go to its front, as a paste of them would put them.
    private func drop(_ ids: [ItemID], on list: ListID) {
        Task { [itemWriter, log] in
            do {
                try await itemWriter.perform { context in
                    if list == .clipboard {
                        try context.moveToFrontOfHistory(ids, clock: Date.init)
                    } else {
                        try context.pin(ids, to: list)
                    }
                }
            } catch {
                log.error("Dropping items on a tab failed: \(error)")
            }
        }
    }

    /// Changes items in a way that cannot be undone, and forgets what could be undone before;
    /// `completion` runs once the change is saved, and not if it fails.
    private func writeIrreversibly(
        _ change: @escaping @Sendable (WritingContext) throws -> Void,
        then completion: (() -> Void)? = nil
    ) {
        Task { [itemWriter, log] in
            do {
                try await itemWriter.performIrreversibly(change)
                completion?()
            } catch {
                log.error("Changing a list failed: \(error)")
            }
        }
    }

    private func write(_ change: @escaping @Sendable (WritingContext) throws -> Void) {
        Task { [writer, log] in
            do {
                try await writer.perform(author: .user, change)
            } catch {
                log.error("Changing a list failed: \(error)")
            }
        }
    }
}

extension ListTabsController: TabMenuActions {
    public func perform(_ command: TabMenuCommand) {
        switch command {
        case .eraseHistory:
            eraseHistory()
        case .deletePinboard(let id):
            deletePinboard(id)
        case .setPinboardColor(let color, let id):
            write { try $0.setPinboardColor(color, of: id) }
        }
    }
}
