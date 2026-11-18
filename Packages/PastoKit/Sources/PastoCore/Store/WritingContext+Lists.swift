import CoreData
import Foundation

// MARK: - Pinboards

extension WritingContext {
    /// Creates a pinboard after the user's last list.
    public func createPinboard(name: String, color: PinboardColor) throws -> ListID {
        let lastIndex = try context.fetch(ListMetadataEntity.makeRequest()).map(\.index).max() ?? -1

        let list = ListEntity(context: context)
        list.identifier = UUID().uuidString
        list.name = name
        list.type = .pinboard
        try list.setAttributes(.pinboard(color: color))
        list.createdAt = now

        let metadata = ListMetadataEntity(context: context)
        metadata.identifier = list.identifier
        metadata.index = lastIndex + 1
        metadata.createdAt = now
        list.metadata = metadata

        return ListID(rawValue: list.identifier)
    }

    public func renameList(_ id: ListID, to name: String) throws {
        let list = try list(id)
        list.name = name
        list.updatedAt = now
    }

    public func setPinboardColor(_ color: PinboardColor, of id: ListID) throws {
        let pinboard = try pinboard(id)
        try pinboard.setAttributes(.pinboard(color: color))
        pinboard.updatedAt = now
    }

    /// Deletes a pinboard. Its items first leave it the way removing them from it does: the
    /// ones that are also in the history stay there, the others are deleted. The clipboard
    /// history cannot be deleted.
    public func deleteList(_ id: ListID) throws {
        let list = try list(id)
        guard list.type != .clipboard else {
            throw StoreError.cannotDeleteClipboardHistory
        }
        list.items.forEach(takeOffPinboard)
        context.delete(list)
    }

    /// Puts the given lists first, in that order; the ones not mentioned follow in their current order.
    public func reorderLists(_ ids: [ListID]) throws {
        // Sorted in memory, not by the fetch, so that it sees what earlier operations of this
        // transaction did.
        let current = try context.fetch(ListEntity.makeRequest()).sorted {
            ($0.metadata?.index ?? 0) < ($1.metadata?.index ?? 0)
        }

        let mentioned = ids.compactMap { id in current.first { $0.identifier == id.rawValue } }
        let ordered = mentioned + current.filter { list in !mentioned.contains { $0 === list } }

        // Only the private order changes: the lists themselves stay untouched, so a shared
        // pinboard does not look modified to the people it is shared with.
        for (index, list) in ordered.enumerated() {
            guard let metadata = list.metadata, metadata.index != Int64(index) else { continue }
            metadata.index = Int64(index)
            metadata.updatedAt = now
        }
    }
}
