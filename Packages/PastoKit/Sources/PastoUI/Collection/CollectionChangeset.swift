import Foundation

/// A content change for a `CollectionView`, in indexes: deletions and move origins refer to
/// the collection before the change, insertions, move destinations and updates to it afterwards.
public nonisolated struct CollectionChangeset: Sendable, Equatable {
    public struct Move: Sendable, Equatable {
        public var from: Int
        public var to: Int

        public init(from: Int, to: Int) {
            self.from = from
            self.to = to
        }
    }

    public var deletions: [Int]
    public var insertions: [Int]
    public var moves: [Move]
    /// Cells that stay but whose content changed.
    public var updates: [Int]

    public init(deletions: [Int] = [], insertions: [Int] = [], moves: [Move] = [], updates: [Int] = []) {
        self.deletions = deletions
        self.insertions = insertions
        self.moves = moves
        self.updates = updates
    }

    public var isEmpty: Bool {
        deletions.isEmpty && insertions.isEmpty && moves.isEmpty && updates.isEmpty
    }

    /// How many cells change position explicitly; large changes are applied as a plain reload.
    public var structuralChangeCount: Int {
        deletions.count + insertions.count + moves.count
    }

    /// Translates indexes between the collection before and after the change without walking
    /// the whole collection: only the (few) changed positions are consulted, so a view with a
    /// handful of visible cells stays cheap however long the collection is.
    func indexMap() -> IndexMap {
        IndexMap(self)
    }

    struct IndexMap {
        private let deleted: Set<Int>
        private let destinationBySource: [Int: Int]
        private let sourceByDestination: [Int: Int]
        private let inserted: Set<Int>
        /// Old positions that do not keep their relative place: deletions and move origins.
        private let vacatedOldIndexes: [Int]
        /// New positions taken by arrivals: insertions and move destinations.
        private let occupiedNewIndexes: [Int]
        /// Each of the lists above minus its position in the list. Both lists are strictly
        /// increasing, so these are non-decreasing and can be binary-searched: "how many slots
        /// must be skipped" becomes a single lookup however many indexes are translated.
        private let vacatedOffsets: [Int]
        private let occupiedOffsets: [Int]

        init(_ changeset: CollectionChangeset) {
            deleted = Set(changeset.deletions)
            inserted = Set(changeset.insertions)
            destinationBySource = Dictionary(changeset.moves.map { ($0.from, $0.to) }) { first, _ in first }
            sourceByDestination = Dictionary(changeset.moves.map { ($0.to, $0.from) }) { first, _ in first }
            vacatedOldIndexes = (changeset.deletions + changeset.moves.map(\.from)).sorted()
            occupiedNewIndexes = (changeset.insertions + changeset.moves.map(\.to)).sorted()
            vacatedOffsets = vacatedOldIndexes.enumerated().map { $1 - $0 }
            occupiedOffsets = occupiedNewIndexes.enumerated().map { $1 - $0 }
        }

        /// Where the cell at `oldIndex` ends up, or nil if it was deleted.
        func newIndex(forOldIndex oldIndex: Int) -> Int? {
            if deleted.contains(oldIndex) { return nil }
            if let destination = destinationBySource[oldIndex] { return destination }
            return compactedIndex(forOldIndex: oldIndex)
        }

        /// Where the cell at `oldIndex` would be if it kept its place among the cells that keep
        /// theirs. For a deleted cell it is where it travels while it fades out, together with
        /// the cells closing its gap.
        func compactedIndex(forOldIndex oldIndex: Int) -> Int {
            // Rank among the cells that keep their relative order, then skip the slots that
            // arrivals occupy in the new collection.
            let rank = oldIndex - Self.count(in: vacatedOldIndexes, below: oldIndex)
            return rank + Self.count(in: occupiedOffsets, upTo: rank)
        }

        /// Where the cell at `newIndex` came from, or nil if it was inserted.
        func oldIndex(forNewIndex newIndex: Int) -> Int? {
            if inserted.contains(newIndex) { return nil }
            if let source = sourceByDestination[newIndex] { return source }
            let rank = newIndex - Self.count(in: occupiedNewIndexes, below: newIndex)
            return rank + Self.count(in: vacatedOffsets, upTo: rank)
        }

        /// How many elements of the sorted `values` are less than `limit`.
        private static func count(in values: [Int], below limit: Int) -> Int {
            partitionPoint(of: values) { $0 < limit }
        }

        /// How many elements of the sorted `values` are less than or equal to `limit`.
        private static func count(in values: [Int], upTo limit: Int) -> Int {
            partitionPoint(of: values) { $0 <= limit }
        }

        /// The number of leading elements of `values` that satisfy `belongsToPrefix`, which must
        /// hold for a prefix of the array and for nothing after it.
        private static func partitionPoint(of values: [Int], where belongsToPrefix: (Int) -> Bool) -> Int {
            var low = 0
            var high = values.count
            while low < high {
                let middle = (low + high) / 2
                if belongsToPrefix(values[middle]) {
                    low = middle + 1
                } else {
                    high = middle
                }
            }
            return low
        }
    }
}
