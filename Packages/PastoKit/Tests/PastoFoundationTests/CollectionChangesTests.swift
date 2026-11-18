import PastoFoundation
import Testing

struct CollectionChangesTests {
    private typealias Changes = CollectionChanges<String>

    private func changes(from old: [String], to new: [String], updated: Set<String> = []) -> Changes {
        .between(CollectionSnapshot(ids: old), CollectionSnapshot(ids: new, updatedIDs: updated))
    }

    // MARK: - The four changes the panel animates

    @Test func insertionAtTheFront() {
        let changes = changes(from: ["a", "b", "c"], to: ["n", "a", "b", "c"])

        #expect(changes == Changes(insertions: [.init(id: "n", index: 0)]))
    }

    @Test func moveToTheFront() {
        let changes = changes(from: ["a", "b", "c", "d"], to: ["c", "a", "b", "d"], updated: ["c"])

        #expect(changes == Changes(moves: [.init(id: "c", from: 2, to: 0)], updates: ["c"]))
    }

    @Test func removalOfOne() {
        let changes = changes(from: ["a", "b", "c"], to: ["a", "c"])

        #expect(changes == Changes(removals: [.init(id: "b", index: 1)]))
    }

    @Test func removalOfSeveralIsInDescendingOrder() {
        let changes = changes(from: ["a", "b", "c", "d", "e"], to: ["b", "d"])

        #expect(changes.removals == [.init(id: "e", index: 4), .init(id: "c", index: 2), .init(id: "a", index: 0)])
        #expect(changes.insertions.isEmpty)
        #expect(changes.moves.isEmpty)
    }

    @Test func updateInPlace() {
        let changes = changes(from: ["a", "b", "c"], to: ["a", "b", "c"], updated: ["b"])

        #expect(changes == Changes(updates: ["b"]))
    }

    // MARK: - Everything else

    @Test func nothingChanged() {
        #expect(changes(from: ["a", "b"], to: ["a", "b"]).isEmpty)
        #expect(changes(from: [], to: []).isEmpty)
    }

    @Test func fromAndToEmpty() {
        #expect(changes(from: [], to: ["a", "b"]).insertions == [.init(id: "a", index: 0), .init(id: "b", index: 1)])
        #expect(changes(from: ["a", "b"], to: []).removals == [.init(id: "b", index: 1), .init(id: "a", index: 0)])
    }

    @Test func updatesOnlyCoverSurvivorsAndFollowTheNewOrder() {
        let changes = changes(from: ["a", "b", "c"], to: ["n", "c", "a"], updated: ["a", "c", "n", "gone"])

        #expect(changes.updates == ["c", "a"])
    }

    @Test func combinedInsertionRemovalAndMove() {
        let changes = changes(from: ["a", "b", "c", "d"], to: ["d", "n", "a", "c"])

        #expect(changes.removals == [.init(id: "b", index: 1)])
        #expect(changes.insertions == [.init(id: "n", index: 1)])
        #expect(changes.moves == [.init(id: "d", from: 3, to: 0)])
    }

    @Test func movesAreTheFewestPossible() {
        // Reversing five elements keeps one in place; rotating by one moves a single element.
        #expect(changes(from: ["a", "b", "c", "d", "e"], to: ["e", "d", "c", "b", "a"]).moves.count == 4)
        #expect(changes(from: ["a", "b", "c", "d", "e"], to: ["b", "c", "d", "e", "a"]).moves == [.init(id: "a", from: 0, to: 4)])
    }

    /// Whatever the two snapshots are, applying the changes to the old one must give the new one.
    @Test func applyingTheChangesAlwaysGivesTheNewOrder() {
        let old = ["a", "b", "c", "d", "e"]
        for permutation in permutations(of: old) {
            let reordered = permutation
            let withRemovals = permutation.filter { $0 != "b" && $0 != "e" }
            let mixed = ["x"] + withRemovals + ["y"]
            for new in [reordered, withRemovals, mixed] {
                let changes = changes(from: old, to: new)
                #expect(apply(changes, to: old) == new, "from \(old) to \(new)")
                // A survivor is never reported as removed and inserted again.
                #expect(Set(changes.removals.map(\.id)).isDisjoint(with: changes.insertions.map(\.id)))
            }
        }
    }

    /// A snapshot must not repeat an identifier; one that does is a fault, not a crash. Each later
    /// copy is a removal or an insertion of its own, so the changes still turn one snapshot into
    /// the other.
    @Test func repeatedIdentifiersStillGiveTheNewOrder() {
        let cases: [(old: [String], new: [String])] = [
            (["a", "b", "c"], ["a", "b", "a", "c"]),
            (["a", "b", "a", "c"], ["a", "b", "c"]),
            (["a", "a", "b"], ["b", "a", "a"]),
            (["a", "b", "b"], ["c", "b", "b", "b"]),
        ]
        for (old, new) in cases {
            let changes = changes(from: old, to: new)
            #expect(apply(changes, to: old) == new, "from \(old) to \(new)")
        }
        #expect(changes(from: ["a", "b"], to: ["a", "b", "a"]) == Changes(insertions: [.init(id: "a", index: 2)]))
    }

    // MARK: - Helpers

    /// Applies changes the way a batch update does: everything that leaves its old position first
    /// (from the back), then everything that arrives at a new position (from the front).
    private func apply(_ changes: Changes, to old: [String]) -> [String] {
        var ids = old
        let leaving = changes.removals.map(\.index) + changes.moves.map(\.from)
        for index in leaving.sorted(by: >) {
            ids.remove(at: index)
        }
        let arriving = changes.insertions.map { (index: $0.index, id: $0.id) } + changes.moves.map { (index: $0.to, id: $0.id) }
        for arrival in arriving.sorted(by: { $0.index < $1.index }) {
            ids.insert(arrival.id, at: arrival.index)
        }
        return ids
    }

    private func permutations(of elements: [String]) -> [[String]] {
        guard let first = elements.first else { return [[]] }
        return permutations(of: Array(elements.dropFirst())).flatMap { rest in
            (0...rest.count).map { index in
                var permutation = rest
                permutation.insert(first, at: index)
                return permutation
            }
        }
    }
}
