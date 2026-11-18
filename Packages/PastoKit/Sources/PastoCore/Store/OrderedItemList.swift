import Foundation

/// The members of an item collection in presentation order, kept in order one change at a time
/// instead of being read again.
///
/// A member is known by a handle — its object ID in the store — and placed by its sort key, then
/// its identifier. A change costs a binary search per member it touches plus one move of the
/// arrays, never a pass that compares or hashes every member.
struct OrderedItemList<Handle: Hashable> {
    struct Member {
        var handle: Handle
        var id: ItemID
        var key: ItemSortKey
    }

    /// Up to this many members are taken out or put in one by one; more, in a single pass.
    private static var individualChangeLimit: Int { 8 }

    /// The identifiers in order: what the collection publishes.
    private(set) var ids: [ItemID] = []
    /// Parallel to `ids`.
    private var handles: [Handle] = []
    private var keys: [Handle: ItemSortKey] = [:]
    /// The keys by position, until `prepare()` builds `keys` from them: indexing a few hundred
    /// thousand members is kept out of the first read, which the main thread waits for.
    private var unindexedKeys: [ItemSortKey]?

    /// - Parameter members: Usually already in order, as a sorted fetch returns them; sorted
    ///   here if they are not.
    init(_ members: [Member]) {
        var members = members
        if !members.indices.dropFirst().allSatisfy({ !Self.precedes(members[$0], members[$0 - 1]) }) {
            members.sort(by: Self.precedes)
        }
        ids = members.map(\.id)
        handles = members.map(\.handle)
        unindexedKeys = members.map(\.key)
    }

    var count: Int { ids.count }

    /// Builds the index of the members by handle, if it is not built yet. Every change does it
    /// first; doing it ahead of time keeps it out of the first change.
    mutating func prepare() {
        guard let pending = unindexedKeys else { return }
        keys.reserveCapacity(pending.count)
        for (handle, key) in zip(handles, pending) {
            keys[handle] = key
        }
        unindexedKeys = nil
    }

    /// Whether `handle` is a member. Only once prepared.
    func contains(_ handle: Handle) -> Bool {
        precondition(unindexedKeys == nil, "An ordered item list answers by handle once prepared")
        return keys[handle] != nil
    }

    /// Takes out the members among `removed`; handles that are not members are ignored.
    /// Returns whether any was.
    @discardableResult
    mutating func remove(_ removed: some Sequence<Handle>) -> Bool {
        prepare()
        let positions = Set(removed.compactMap(position(of:)))
        guard !positions.isEmpty else { return false }
        for handle in positions.map({ handles[$0] }) {
            keys[handle] = nil
        }
        if positions.count <= Self.individualChangeLimit {
            for position in positions.sorted(by: >) {
                ids.remove(at: position)
                handles.remove(at: position)
            }
        } else {
            // Every survivor after the first gap moves down once.
            let gaps = positions.sorted()
            var nextGap = 0
            var kept = gaps[0]
            for position in gaps[0]..<ids.count {
                if nextGap < gaps.count, gaps[nextGap] == position {
                    nextGap += 1
                    continue
                }
                ids.swapAt(kept, position)
                handles.swapAt(kept, position)
                kept += 1
            }
            ids.removeSubrange(kept...)
            handles.removeSubrange(kept...)
        }
        return true
    }

    /// Puts each member in its place. None may be a member already.
    mutating func insert(_ members: [Member]) {
        guard !members.isEmpty else { return }
        prepare()
        for member in members {
            keys[member.handle] = member.key
        }
        if members.count <= Self.individualChangeLimit {
            for member in members {
                let position = insertionPosition(for: member)
                ids.insert(member.id, at: position)
                handles.insert(member.handle, at: position)
            }
            return
        }

        // Many at once: one merge of two sorted runs.
        let arriving = members.sorted(by: Self.precedes)
        var mergedIDs: [ItemID] = []
        var mergedHandles: [Handle] = []
        mergedIDs.reserveCapacity(ids.count + arriving.count)
        mergedHandles.reserveCapacity(ids.count + arriving.count)
        var current = 0
        for member in arriving {
            while current < ids.count, Self.precedes(self.member(at: current), member) {
                mergedIDs.append(ids[current])
                mergedHandles.append(handles[current])
                current += 1
            }
            mergedIDs.append(member.id)
            mergedHandles.append(member.handle)
        }
        mergedIDs.append(contentsOf: ids[current...])
        mergedHandles.append(contentsOf: handles[current...])
        ids = mergedIDs
        handles = mergedHandles
    }

    // MARK: - Order

    /// Whether `first` comes before `second`: by key, then by identifier, descending, as the store's binary
    /// collation compares them (bytes of UTF-8).
    static func precedes(_ first: Member, _ second: Member) -> Bool {
        if first.key != second.key {
            return first.key < second.key
        }
        return second.id.rawValue.utf8.lexicographicallyPrecedes(first.id.rawValue.utf8)
    }

    private func member(at position: Int) -> Member {
        Member(handle: handles[position], id: ids[position], key: keys[handles[position]]!)
    }

    /// The first position whose member does not come before `member`.
    private func insertionPosition(for member: Member) -> Int {
        var low = 0
        var high = ids.count
        while low < high {
            let middle = (low + high) / 2
            if Self.precedes(self.member(at: middle), member) {
                low = middle + 1
            } else {
                high = middle
            }
        }
        return low
    }

    private func position(of handle: Handle) -> Int? {
        guard let key = keys[handle] else { return nil }
        // The first member with this key, then along the members that share it.
        var low = 0
        var high = ids.count
        while low < high {
            let middle = (low + high) / 2
            if keys[handles[middle]]! < key {
                low = middle + 1
            } else {
                high = middle
            }
        }
        var position = low
        while position < handles.count, keys[handles[position]] == key {
            if handles[position] == handle { return position }
            position += 1
        }
        return nil
    }
}
