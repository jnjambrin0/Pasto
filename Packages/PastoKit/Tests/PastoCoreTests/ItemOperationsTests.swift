import Foundation
import PastoCore
import PastoFoundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ItemOperationsTests {
    private let store: StoreFixture

    init() throws {
        store = try StoreFixture()
    }

    @Test func setTitleAndTouch() async throws {
        let id = try await store.record(["a"])[0]

        try await store.writer.perform(author: .user) { context in
            try context.setTitle("Greeting", of: id)
            try context.touch(id, at: .second(50))
        }

        let item = try #require(store.reader.item(id))
        #expect(item.title == "Greeting")
        #expect(item.timestamp == .second(50))
    }

    @Test func replaceContentKeepsTheItemAndChangesWhatItHolds() async throws {
        let id = try await store.record(["draft"], startingAt: 5)[0]

        try await store.writer.perform(author: .user) { context in
            try context.replaceContent(of: id, with: .text("final", at: 99))
        }
        // The checksum followed the content: capturing the new text finds this item.
        let outcome = try await store.writer.perform(author: .capture) { context in
            try context.record(.text("final", at: 6))
        }

        // It was already the newest item of the history.
        #expect(outcome == RecordOutcome(id: id, kind: .movedToFront, didChangeNewestItem: false))
        let item = try #require(store.reader.item(id))
        #expect(item.preview == .text(TextPreview(text: "final", characterCount: 5)))
        #expect(store.reader.pasteboardItems(for: id) == NewItem.text("final", at: 0).pasteboardItems)
        #expect(store.reader.itemCount(in: .clipboard) == 1)
    }

    @Test func duplicateCopiesTheItemToTheFrontAndToTheEndOfItsPinboard() async throws {
        let ids = try await store.record(["a", "b"])
        let (pinboard, copy) = try await store.writer.perform(author: .user) { context in
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.pin(ids, to: pinboard)
            try context.setTitle("Original", of: ids[0])
            return (pinboard, try context.duplicate(ids[0]))
        }

        #expect(!ids.contains(copy))
        let items = store.reader.items([ids[0], copy])
        try #require(items.count == 2)
        #expect(items[1].title == "Original")
        #expect(items[1].preview == items[0].preview)
        #expect(items[1].timestamp == StoreFixture.now)
        #expect(store.reader.pasteboardItems(for: copy) == store.reader.pasteboardItems(for: ids[0]))
        // Pinning puts each item first, so "b" precedes "a"; the copy goes last.
        #expect(store.reader.itemCollection(for: pinboard).snapshot.ids == [ids[1], ids[0], copy])
        #expect(store.reader.itemCollection(for: .clipboard).snapshot.ids == [copy, ids[1], ids[0]])
    }

    @Test func deleteRemovesItemsAndSkipsUnknownOnes() async throws {
        let ids = try await store.record(["a", "b", "c"])

        try await store.writer.perform(author: .user) { context in
            try context.delete([ids[0], ItemID(rawValue: "gone"), ids[2]])
        }

        #expect(store.reader.items(ids).map(\.id) == [ids[1]])
        #expect(store.reader.pasteboardItems(for: ids[0]) == nil)
    }

    @Test func operationsOnAMissingItemThrow() async throws {
        let missing = ItemID(rawValue: "missing")

        await #expect(throws: StoreError.itemNotFound) {
            try await store.writer.perform(author: .user) { try $0.setTitle("x", of: missing) }
        }
        await #expect(throws: StoreError.itemNotFound) {
            try await store.writer.perform(author: .user) { _ = try $0.duplicate(missing) }
        }
    }

    @Test func aFailedTransactionLeavesNothingBehind() async throws {
        await #expect(throws: StoreError.listNotFound) {
            try await store.writer.perform(author: .user) { context in
                _ = try context.record(.text("a", at: 1))
                _ = try context.createPinboard(name: "Work", color: .blue)
                try context.renameList(ListID(rawValue: "missing"), to: "x")
            }
        }

        // The writer is usable again and none of the failed work was kept.
        let ids = try await store.record(["b"])
        #expect(store.reader.itemCollection(for: .clipboard).snapshot.ids == ids)
        #expect(store.reader.lists().map(\.id) == [.clipboard])
    }
}
