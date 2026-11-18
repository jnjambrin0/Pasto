import Testing
@testable import PastoUI

@Suite struct CollectionChangesetTests {
    /// Applies a changeset to a list of labels the slow, obvious way, to check the index map against.
    private func apply(_ changeset: CollectionChangeset, to old: [String], inserting new: [String]) -> [String] {
        let moved = Dictionary(uniqueKeysWithValues: changeset.moves.map { ($0.to, old[$0.from]) })
        let leaving = Set(changeset.deletions + changeset.moves.map(\.from))
        var stationary = old.indices.filter { !leaving.contains($0) }.map { old[$0] }[...]
        var arrivals = new[...]
        let count = old.count - changeset.deletions.count + changeset.insertions.count
        return (0..<count).map { index in
            if changeset.insertions.contains(index) { return arrivals.removeFirst() }
            if let label = moved[index] { return label }
            return stationary.removeFirst()
        }
    }

    private func check(_ changeset: CollectionChangeset, old: [String], inserting new: [String] = []) {
        let result = apply(changeset, to: old, inserting: new)
        let map = changeset.indexMap()
        for (oldIndex, label) in old.enumerated() {
            let expected = result.firstIndex(of: label)
            #expect(map.newIndex(forOldIndex: oldIndex) == expected, "old \(oldIndex) (\(label))")
        }
        for (newIndex, label) in result.enumerated() {
            let expected = old.firstIndex(of: label)
            #expect(map.oldIndex(forNewIndex: newIndex) == expected, "new \(newIndex) (\(label))")
        }
    }

    let old = ["a", "b", "c", "d", "e", "f"]

    @Test func insertionAtTheFront() {
        check(CollectionChangeset(insertions: [0]), old: old, inserting: ["x"])
    }

    @Test func moveToTheFront() {
        check(CollectionChangeset(moves: [.init(from: 3, to: 0)]), old: old)
    }

    @Test func deletions() {
        check(CollectionChangeset(deletions: [1, 4]), old: old)
        check(CollectionChangeset(deletions: [0, 1, 2, 3, 4, 5]), old: old)
    }

    /// A deleted cell travels with the cells that close its gap: where it would be had it stayed.
    @Test func deletedCellsGoWhereTheGapCloses() {
        let neighbours = CollectionChangeset(deletions: [2, 3]).indexMap()
        #expect(neighbours.compactedIndex(forOldIndex: 2) == 2)
        #expect(neighbours.compactedIndex(forOldIndex: 3) == 2)
        #expect(neighbours.newIndex(forOldIndex: 4) == 2)

        let apart = CollectionChangeset(deletions: [1, 4]).indexMap()
        #expect(apart.compactedIndex(forOldIndex: 1) == 1)
        #expect(apart.compactedIndex(forOldIndex: 4) == 3)

        // An insertion at the front pushes the place along, as it does the cell after the gap.
        let withInsertion = CollectionChangeset(deletions: [2], insertions: [0]).indexMap()
        #expect(withInsertion.compactedIndex(forOldIndex: 2) == 3)
        #expect(withInsertion.newIndex(forOldIndex: 3) == 3)
    }

    @Test func mixedChanges() {
        check(
            CollectionChangeset(deletions: [1], insertions: [0, 3], moves: [.init(from: 5, to: 1)]),
            old: old,
            inserting: ["x", "y"]
        )
        check(
            CollectionChangeset(deletions: [0], insertions: [5], moves: [.init(from: 1, to: 3), .init(from: 4, to: 0)]),
            old: old,
            inserting: ["z"]
        )
    }

    /// The index map answers with binary searches; this compares it with the slow model on
    /// changesets of every shape.
    @Test func randomChangesetsMatchTheSlowModel() {
        var generator = SplitMix64(seed: 2026)
        for _ in 0..<200 {
            let oldCount = Int.random(in: 0...24, using: &generator)
            let old = (0..<oldCount).map { "o\($0)" }
            var leaving = Array(old.indices).shuffled(using: &generator)
            let deletions = Array(leaving.prefix(Int.random(in: 0...oldCount / 2, using: &generator)))
            leaving.removeFirst(deletions.count)
            let origins = Array(leaving.prefix(Int.random(in: 0...leaving.count / 2, using: &generator)))

            let insertionCount = Int.random(in: 0...8, using: &generator)
            let newCount = oldCount - deletions.count + insertionCount
            let arrivals = Array((0..<newCount).shuffled(using: &generator).prefix(insertionCount + origins.count))
            let changeset = CollectionChangeset(
                deletions: deletions,
                insertions: Array(arrivals.prefix(insertionCount)),
                moves: zip(origins, arrivals.dropFirst(insertionCount)).map { .init(from: $0, to: $1) }
            )
            check(changeset, old: old, inserting: (0..<insertionCount).map { "n\($0)" })
        }
    }

    @Test func countsStructuralChanges() {
        let changeset = CollectionChangeset(deletions: [1], insertions: [0, 3], moves: [.init(from: 5, to: 1)], updates: [2])
        #expect(changeset.structuralChangeCount == 4)
        #expect(!changeset.isEmpty)
        #expect(CollectionChangeset().isEmpty)
    }
}

/// A small deterministic generator, so that a failure can be reproduced.
private struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
