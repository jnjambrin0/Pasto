import PastoFoundation
import Testing
@testable import PastoUI

@Suite struct SnapshotApplierTests {
    private func snapshot(_ ids: [String], updated: Set<String> = []) -> CollectionSnapshot<String> {
        CollectionSnapshot(ids: ids, updatedIDs: updated)
    }

    @Test func theFirstSnapshotReloads() {
        var applier = SnapshotApplier<String>()
        #expect(applier.apply(snapshot(["a", "b"])) == .reload)
        #expect(applier.ids == ["a", "b"])
    }

    @Test func anIdenticalSnapshotDoesNothing() {
        var applier = SnapshotApplier<String>()
        _ = applier.apply(snapshot(["a", "b"]))
        #expect(applier.apply(snapshot(["a", "b"])) == .none)
    }

    @Test func insertionAtTheFront() {
        var applier = SnapshotApplier<String>()
        _ = applier.apply(snapshot(["a", "b", "c"]))
        #expect(applier.apply(snapshot(["new", "a", "b", "c"])) == .changes(CollectionChangeset(insertions: [0])))
    }

    @Test func recopyIsOneMoveToTheFront() {
        var applier = SnapshotApplier<String>()
        _ = applier.apply(snapshot(["a", "b", "c", "d"]))
        #expect(applier.apply(snapshot(["c", "a", "b", "d"])) == .changes(CollectionChangeset(moves: [.init(from: 2, to: 0)])))
    }

    @Test func deletionsAndUpdates() {
        var applier = SnapshotApplier<String>()
        _ = applier.apply(snapshot(["a", "b", "c", "d"]))
        let application = applier.apply(snapshot(["a", "d"], updated: ["d"]))
        #expect(application == .changes(CollectionChangeset(deletions: [2, 1], updates: [1])))
    }

    @Test func largeChangesReloadInsteadOfAnimating() {
        var applier = SnapshotApplier<Int>()
        _ = applier.apply(CollectionSnapshot(ids: Array(0..<10)))
        let limit = SnapshotApplier<Int>.batchUpdateLimit
        #expect(applier.apply(CollectionSnapshot(ids: Array(0..<(10 + limit)))) != .reload)
        #expect(applier.apply(CollectionSnapshot(ids: Array(0..<(10 + 2 * limit + 1)))) == .reload)
    }
}
