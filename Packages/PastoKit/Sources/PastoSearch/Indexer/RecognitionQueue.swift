import PastoCore

/// Image items waiting for their text to be read: first in first out, each one once. Membership
/// is kept apart from the order, so that queuing a whole history of images does not search the
/// queue once per image.
struct RecognitionQueue: Equatable, Sendable {
    /// In the order they will be read.
    private(set) var ids: [ItemID] = []
    private var members: Set<ItemID> = []

    init(_ ids: some Sequence<ItemID> = []) {
        append(ids)
    }

    var isEmpty: Bool { ids.isEmpty }

    /// Adds at the back the items that are not queued yet.
    ///
    /// - Returns: Those added, in order.
    @discardableResult
    mutating func append(_ newIDs: some Sequence<ItemID>) -> [ItemID] {
        var added: [ItemID] = []
        for id in newIDs where members.insert(id).inserted {
            ids.append(id)
            added.append(id)
        }
        return added
    }

    /// Takes the next item off the front.
    mutating func popFirst() -> ItemID? {
        guard !ids.isEmpty else { return nil }
        let id = ids.removeFirst()
        members.remove(id)
        return id
    }

    /// Puts an item back at the front, for one whose reading was interrupted.
    mutating func putBack(_ id: ItemID) {
        guard members.insert(id).inserted else { return }
        ids.insert(id, at: 0)
    }

    mutating func remove(_ removed: Set<ItemID>) {
        guard !members.isDisjoint(with: removed) else { return }
        ids.removeAll(where: removed.contains)
        members.subtract(removed)
    }
}
