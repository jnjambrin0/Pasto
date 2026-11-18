import CoreData
import Foundation

// Where an item is: in the history, on a pinboard, or both (`ItemListQuery`). These are the
// operations that move items between those places.

extension WritingContext {
    /// Puts the items on `list`. Each one goes to the front, in the order given, so the last
    /// one ends up first. An item already there keeps its position; one that was on another
    /// pinboard leaves it, since an item is on one pinboard at most. The history is not
    /// affected: a pinned item stays in it.
    public func pin(_ ids: [ItemID], to list: ListID) throws {
        let pinboard = try pinboard(list)
        var ordered = orderedItems(of: pinboard)
        for item in try items(ids) where item.list !== pinboard {
            item.list = pinboard
            item.updatedAt = now
            ordered.insert(item, at: 0)
        }
        renumber(ordered)
    }

    /// Takes the items off their pinboards. They stay in the history, where their last use
    /// placed them; one that was not in the history is deleted.
    public func unpin(_ ids: [ItemID]) throws {
        for item in try items(ids) {
            takeOffPinboard(item)
        }
    }

    /// Takes the items out of `list` — the history or a pinboard — and nothing else: an item
    /// that is also somewhere else stays there, and one that is not is deleted. Items that are
    /// not in `list` are left alone.
    public func remove(_ ids: [ItemID], from list: ListID) throws {
        let list = try self.list(list)
        for item in try items(ids) {
            switch list.type {
            case .clipboard:
                takeOutOfHistory(item)
            case .pinboard:
                if item.list === list { takeOffPinboard(item) }
            }
        }
    }

    /// Reorders a pinboard: its items among `ids` end up together, in the order they had, in
    /// front of the item that was at `index` (after the last one when `index` is the count).
    /// Items that are not on `list` are ignored.
    public func moveItems(_ ids: [ItemID], toIndex index: Int, in list: ListID) throws {
        let pinboard = try pinboard(list)
        let current = orderedItems(of: pinboard)
        let moved = Set(try items(ids).map(ObjectIdentifier.init))
        let offsets = IndexSet(current.indices.filter { moved.contains(ObjectIdentifier(current[$0])) })
        renumber(current.moving(fromOffsets: offsets, toOffset: index))
    }
}

// MARK: - Building blocks

extension WritingContext {
    func takeOutOfHistory(_ item: ItemEntity) {
        guard item.timestamp != nil else { return }
        item.timestamp = nil
        item.updatedAt = now
        deleteIfNowhere(item)
    }

    /// The position the item had is left as it was, and the pinboard is not renumbered: a gap
    /// does not change the order.
    func takeOffPinboard(_ item: ItemEntity) {
        guard item.list != nil else { return }
        item.list = nil
        item.updatedAt = now
        deleteIfNowhere(item)
    }

    /// An item that is neither in the history nor on a pinboard is shown nowhere: it goes.
    func deleteIfNowhere(_ item: ItemEntity) {
        if item.timestamp == nil, item.list == nil {
            context.delete(item)
        }
    }

    /// Makes the positions of a pinboard's items 0, 1, 2…, writing only the ones that change.
    private func renumber(_ items: [ItemEntity]) {
        for (index, item) in items.enumerated() where item.displayOrderInPinboard != Int64(index) {
            item.displayOrderInPinboard = Int64(index)
            item.updatedAt = now
        }
    }
}
