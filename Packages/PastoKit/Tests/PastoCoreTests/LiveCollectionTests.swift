import Foundation
import PastoCore
import PastoFoundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct LiveCollectionTests {
    private let store: StoreFixture

    init() throws {
        store = try StoreFixture()
    }

    // MARK: - Items

    @Test func theHistoryIsNewestFirstAndPublishesEveryWrite() async throws {
        let existing = try await store.record(["a", "b"])
        let history = store.reader.itemCollection(for: .clipboard)
        #expect(history.snapshot == CollectionSnapshot(ids: [existing[1], existing[0]]))

        // A capture is an insertion at the front.
        var previous = history.snapshot
        let captured = try await history.change { try await store.record(["c"], startingAt: 3)[0] }
        #expect(captured.snapshot == CollectionSnapshot(ids: [captured.result, existing[1], existing[0]]))
        #expect(CollectionChanges.between(previous, captured.snapshot).insertions == [.init(id: captured.result, index: 0)])

        // Copying again something it already has is a move to the front.
        previous = history.snapshot
        let recopied = try await history.change {
            try await store.writer.perform(author: .capture) { _ = try $0.record(.text("a", at: 4)) }
        }
        #expect(recopied.snapshot == CollectionSnapshot(ids: [existing[0], captured.result, existing[1]], updatedIDs: [existing[0]]))
        #expect(CollectionChanges.between(previous, recopied.snapshot).moves == [.init(id: existing[0], from: 2, to: 0)])

        // A change that does not affect the order is an update in place.
        let renamed = try await history.change {
            try await store.writer.perform(author: .user) { try $0.setTitle("B", of: existing[1]) }
        }
        #expect(renamed.snapshot == CollectionSnapshot(ids: [existing[0], captured.result, existing[1]], updatedIDs: [existing[1]]))
        #expect(store.reader.item(existing[1])?.title == "B")

        let deleted = try await history.change {
            try await store.writer.perform(author: .user) { try $0.delete([existing[0], existing[1]]) }
        }
        #expect(deleted.snapshot == CollectionSnapshot(ids: [captured.result]))
        #expect(history.snapshot == deleted.snapshot)
    }

    @Test func aPinboardFollowsItsOwnOrderAndOnlyItsItems() async throws {
        let items = try await store.record(["a", "b", "c"])
        let pinboard = try await store.writer.perform(author: .user) { try $0.createPinboard(name: "Work", color: .blue) }
        let collection = store.reader.itemCollection(for: pinboard)
        #expect(collection.snapshot.ids.isEmpty)

        let pinned = try await collection.change {
            try await store.writer.perform(author: .user) { try $0.pin([items[1], items[2], items[0]], to: pinboard) }
        }
        // Each item goes first, so the last one pinned leads.
        #expect(pinned.snapshot.ids == [items[0], items[2], items[1]])

        let moved = try await collection.change {
            try await store.writer.perform(author: .user) { try $0.moveItems([items[1]], toIndex: 0, in: pinboard) }
        }
        #expect(moved.snapshot.ids == [items[1], items[0], items[2]])

        let unpinned = try await collection.change {
            try await store.writer.perform(author: .user) { try $0.unpin([items[0]]) }
        }
        #expect(unpinned.snapshot.ids == [items[1], items[2]])
    }

    @Test func theHistoryKeepsPinnedItemsAndLosesTheOnesRemovedFromIt() async throws {
        let items = try await store.record(["a", "b"])
        let history = store.reader.itemCollection(for: .clipboard)
        let pinboard = try await store.writer.perform(author: .user) { context in
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.pin([items[0]], to: pinboard)
            return pinboard
        }
        #expect(store.reader.itemCollection(for: .clipboard).snapshot.ids == [items[1], items[0]])

        let removed = try await history.change {
            try await store.writer.perform(author: .user) { try $0.remove([items[0]], from: .clipboard) }
        }
        #expect(removed.snapshot.ids == [items[1]])
        #expect(store.reader.itemCollection(for: pinboard).snapshot.ids == [items[0]])
    }

    // MARK: - Lists

    @Test func theListsFollowTheUsersOrderAndPublishEveryWrite() async throws {
        let lists = store.reader.listCollection()
        #expect(lists.snapshot == CollectionSnapshot(ids: [.clipboard]))

        let created = try await lists.change {
            try await store.writer.perform(author: .user) { context in
                [try context.createPinboard(name: "Work", color: .blue), try context.createPinboard(name: "Home", color: .red)]
            }
        }
        let (work, home) = (created.result[0], created.result[1])
        #expect(created.snapshot == CollectionSnapshot(ids: [.clipboard, work, home]))

        let renamed = try await lists.change {
            try await store.writer.perform(author: .user) { try $0.renameList(home, to: "Family") }
        }
        #expect(renamed.snapshot == CollectionSnapshot(ids: [.clipboard, work, home], updatedIDs: [home]))

        // The order lives outside the lists themselves: a reorder moves them without updating any.
        let reordered = try await lists.change {
            try await store.writer.perform(author: .user) { try $0.reorderLists([.clipboard, home, work]) }
        }
        #expect(reordered.snapshot == CollectionSnapshot(ids: [.clipboard, home, work]))

        let deleted = try await lists.change {
            try await store.writer.perform(author: .user) { try $0.deleteList(home) }
        }
        #expect(deleted.snapshot == CollectionSnapshot(ids: [.clipboard, work]))
        #expect(lists.snapshot == deleted.snapshot)
    }
}
