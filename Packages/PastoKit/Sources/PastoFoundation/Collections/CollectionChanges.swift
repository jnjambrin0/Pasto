import os

/// What turns one `CollectionSnapshot` into the next, in the terms a batch update needs: removals
/// and move origins refer to the old snapshot, insertions and move destinations to the new one.
public struct CollectionChanges<ID: Hashable & Sendable>: Sendable, Equatable {
    public struct Removal: Sendable, Equatable {
        public var id: ID
        /// Index in the old snapshot.
        public var index: Int

        public init(id: ID, index: Int) {
            self.id = id
            self.index = index
        }
    }

    public struct Insertion: Sendable, Equatable {
        public var id: ID
        /// Index in the new snapshot.
        public var index: Int

        public init(id: ID, index: Int) {
            self.id = id
            self.index = index
        }
    }

    public struct Move: Sendable, Equatable {
        public var id: ID
        /// Index in the old snapshot.
        public var from: Int
        /// Index in the new snapshot.
        public var to: Int

        public init(id: ID, from: Int, to: Int) {
            self.id = id
            self.from = from
            self.to = to
        }
    }

    /// By descending index, so they can be applied one by one.
    public var removals: [Removal]
    /// By ascending index, so they can be applied one by one.
    public var insertions: [Insertion]
    /// By ascending destination.
    public var moves: [Move]
    /// Surviving elements whose content changed, in the new order. A moved element can also be here.
    public var updates: [ID]

    public init(removals: [Removal] = [], insertions: [Insertion] = [], moves: [Move] = [], updates: [ID] = []) {
        self.removals = removals
        self.insertions = insertions
        self.moves = moves
        self.updates = updates
    }

    public var isEmpty: Bool {
        removals.isEmpty && insertions.isEmpty && moves.isEmpty && updates.isEmpty
    }

    /// Up to this many elements in both snapshots together, every difference goes through the
    /// general algorithm; above, the shortcuts of `largeDifference` come first.
    @inlinable static var largeCollectionThreshold: Int { 2_048 }

    /// The difference from `old` to `new`.
    ///
    /// An element present in both whose position relative to the other survivors changed is a move,
    /// never a removal plus an insertion; the set of moves is the smallest possible.
    ///
    /// For large snapshots the work is proportional to the length of the snapshots plus what
    /// changed, without hashing every element, as long as what changed is small: one or a few
    /// insertions, removals or moves anywhere, or any number of only insertions or only removals.
    /// When several minimal sets of moves exist, a large snapshot may get a different one than
    /// the general algorithm would choose.
    @inlinable public static func between(_ old: CollectionSnapshot<ID>, _ new: CollectionSnapshot<ID>) -> CollectionChanges<ID> {
        var changes = old.ids.count + new.ids.count <= largeCollectionThreshold
            ? difference(old.ids[...], new.ids[...])
            : largeDifference(old.ids, new.ids) ?? difference(old.ids[...], new.ids[...])
        changes.addUpdates(of: new)
        return changes
    }

    /// The difference from `old` to `new`, as `between(_:_:)` finds it — or `nil` when it has more
    /// than `changeLimit` removals, insertions and moves together: what a collection view reloads
    /// rather than animates. How much more is not worked out, so a large snapshot never needs the
    /// general algorithm, whose cost grows with the length of the snapshots whatever changed.
    @inlinable public static func between(
        _ old: CollectionSnapshot<ID>,
        _ new: CollectionSnapshot<ID>,
        changeLimit: Int
    ) -> CollectionChanges<ID>? {
        var changes: CollectionChanges<ID>
        if old.ids.count + new.ids.count <= largeCollectionThreshold {
            changes = difference(old.ids[...], new.ids[...])
        } else if let large = largeDifference(old.ids, new.ids, changeLimit: changeLimit) {
            changes = large
        } else {
            return nil
        }
        guard changes.removals.count + changes.insertions.count + changes.moves.count <= changeLimit else { return nil }
        changes.addUpdates(of: new)
        return changes
    }

    /// Updated survivors, in the new order: an element of the new snapshot that was not inserted.
    @inlinable mutating func addUpdates(of new: CollectionSnapshot<ID>) {
        guard !new.updatedIDs.isEmpty else { return }
        let inserted = Set(insertions.map(\.index))
        updates = new.indexes(of: new.updatedIDs)
            .filter { !inserted.contains($0) }
            .map { new.ids[$0] }
    }

    /// The general algorithm, on the part of two snapshots that differs; indexes are those of the
    /// whole snapshots. Hashes every element of both parts.
    @inlinable static func difference(_ old: ArraySlice<ID>, _ new: ArraySlice<ID>) -> CollectionChanges<ID> {
        let (oldIndexByID, oldRepeats) = indexByID(old)
        let (newIndexByID, newRepeats) = indexByID(new)

        // A repeated identifier, which a snapshot must not hold, counts as a different element
        // at each later position: removed from the old snapshot, inserted in the new one. The
        // changes still turn one into the other, so a view applying them stays consistent.
        let removals = old.indices.reversed().compactMap { index in
            newIndexByID[old[index]] == nil || oldRepeats.contains(index) ? Removal(id: old[index], index: index) : nil
        }
        let insertions = new.indices.compactMap { index in
            oldIndexByID[new[index]] == nil || newRepeats.contains(index) ? Insertion(id: new[index], index: index) : nil
        }

        // Survivors in their old order. The longest run of them that is still in ascending order in
        // the new snapshot can stay where it is; every other survivor has to move.
        let survivors = old.indices.compactMap { oldIndex -> Move? in
            guard !oldRepeats.contains(oldIndex) else { return nil }
            let id = old[oldIndex]
            return newIndexByID[id].map { Move(id: id, from: oldIndex, to: $0) }
        }
        let stationary = longestIncreasingSubsequence(survivors.map(\.to))
        let moves = survivors.indices
            .filter { !stationary.contains($0) }
            .map { survivors[$0] }
            .sorted { $0.to < $1.to }

        return CollectionChanges(removals: removals, insertions: insertions, moves: moves)
    }

    /// Where each element is. A snapshot cannot hold the same identifier twice; if one does, the
    /// identifier keeps its first position and the later ones come back in `repeats`. It is a
    /// fault, logged as one, but no reason to quit.
    @inlinable static func indexByID(_ ids: ArraySlice<ID>) -> (indexByID: [ID: Int], repeats: Set<Int>) {
        var indexByID: [ID: Int] = [:]
        var repeats: Set<Int> = []
        indexByID.reserveCapacity(ids.count)
        for index in ids.indices {
            if let first = indexByID.updateValue(index, forKey: ids[index]) {
                indexByID[ids[index]] = first
                repeats.insert(index)
            }
        }
        if !repeats.isEmpty {
            reportRepeatedIdentifiers(count: repeats.count)
        }
        return (indexByID, repeats)
    }

    @usableFromInline static func reportRepeatedIdentifiers(count: Int) {
        Log.logger(.app).fault("A collection snapshot holds \(count, privacy: .public) repeated identifiers")
    }

    /// Positions in `values` of one longest strictly increasing subsequence (patience sorting).
    @inlinable static func longestIncreasingSubsequence(_ values: [Int]) -> Set<Int> {
        // tails[k]: position of the smallest value that ends an increasing subsequence of length k + 1.
        var tails: [Int] = []
        var predecessors = [Int?](repeating: nil, count: values.count)

        for position in values.indices {
            var low = 0
            var high = tails.count
            while low < high {
                let middle = (low + high) / 2
                if values[tails[middle]] < values[position] {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            if low > 0 {
                predecessors[position] = tails[low - 1]
            }
            if low == tails.count {
                tails.append(position)
            } else {
                tails[low] = position
            }
        }

        var positions: Set<Int> = []
        var cursor = tails.last
        while let position = cursor {
            positions.insert(position)
            cursor = predecessors[position]
        }
        return positions
    }
}
