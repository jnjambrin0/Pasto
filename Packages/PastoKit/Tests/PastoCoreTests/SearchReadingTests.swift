import Foundation
import PastoCore
import PastoFoundation
import Testing

/// The reads search is built on: `IndexableItemReader` and the search queries of `StoreReader`.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SearchReadingTests {
    private let mail = SourceApplication(bundleIdentifier: "com.example.mail", name: "Mail")

    @Test func indexableItemsCarryWhatTheyAreFoundBy() async throws {
        let fixture = try StoreFixture()
        let indexable = IndexableItemReader(stack: fixture.stack)
        let (plain, pinned) = try await fixture.writer.perform(author: .capture) { [mail] context in
            let plain = try context.record(.text("alpha", at: 1, from: mail)).id
            let pinned = try context.record(.text("beta", at: 2)).id
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.setTitle("Named", of: pinned)
            try context.pin([pinned], to: pinboard)
            return (plain, pinned)
        }

        #expect(try await indexable.itemIDs() == [pinned, plain])
        #expect(try await indexable.itemIDs(before: .second(2)) == [plain])

        let items = try await indexable.items([plain, pinned, ItemID(rawValue: "gone")])
        #expect(items.map(\.id) == [pinned, plain])
        #expect(items[0].title == "Named")
        #expect(items[0].text == "beta")
        #expect(items[0].pinboardID != nil)
        #expect(items[0].deviceName == "Test Mac")
        #expect(items[1].applicationName == "Mail")
        #expect(items[1].pinboardID == nil)
        #expect(items[1].timestamp == .second(1))

        #expect(indexable.storeIdentifier != nil)
        #expect(try await indexable.imageData(for: plain) == nil)
    }

    @Test func anItemOnlyOnAPinboardIsAsOldAsItsCreation() async throws {
        let fixture = try StoreFixture()
        let indexable = IndexableItemReader(stack: fixture.stack)
        let ids = try await fixture.record(["a", "b", "c"])
        try await fixture.writer.perform(author: .user) { context in
            try context.pin([ids[0]], to: try context.createPinboard(name: "Work", color: .blue))
            try context.remove([ids[0]], from: .clipboard)
        }

        // Created at the fixture's clock, well after the others were last used.
        #expect(try await indexable.itemIDs() == [ids[0], ids[2], ids[1]])
        // Going on from an item indexed earlier does not index it again.
        #expect(try await indexable.itemIDs(before: .second(3)) == [ids[1]])
    }

    @Test func readerListsSourcesWithItemsAndOrdersResultsNewestFirst() async throws {
        let fixture = try StoreFixture()
        let collection = fixture.reader.itemCollection(for: .clipboard)
        let merged = AsyncStream<Void> { continuation in
            collection.onChange = { _ in continuation.yield() }
        }

        let ids = try await fixture.writer.perform(author: .capture) { [mail] context in
            try context.upsertApplication(SourceApplication(bundleIdentifier: "com.example.unused", name: "Unused"))
            let notes = SourceApplication(bundleIdentifier: "com.example.notes", name: "Notes")
            return try [
                context.record(.text("a", at: 1, from: notes)).id,
                context.record(.text("b", at: 2, from: mail)).id,
                context.record(.text("c", at: 3, from: mail)).id,
            ]
        }
        var merges = merged.makeAsyncIterator()
        await merges.next()

        #expect(fixture.reader.sourceApplicationNames() == ["Mail", "Notes"])
        #expect(fixture.reader.deviceNames() == ["Test Mac"])
        #expect(fixture.reader.sourceApplication(named: "Notes")?.bundleIdentifier == "com.example.notes")
        #expect(fixture.reader.sourceApplication(named: "Pages") == nil)
        #expect(fixture.reader.device(named: "Test Mac")?.type == .mac)
        #expect(fixture.reader.device(named: "Other Mac") == nil)
        #expect(fixture.reader.itemIDs(among: [ids[0], ItemID(rawValue: "gone"), ids[2]]) == [ids[2], ids[0]])
    }

    @Test func liveResultsFollowTheStoreWithoutTakingInNewItems() async throws {
        let fixture = try StoreFixture()
        let ids = try await fixture.record(["a", "b", "c"])
        let results = fixture.reader.itemCollection(among: [ids[0], ids[1], ItemID(rawValue: "gone")])
        #expect(results.snapshot == CollectionSnapshot(ids: [ids[1], ids[0]]))

        // Copied again, a result moves to the front. A new item is not a result, whatever it holds.
        let recopied = try await results.change {
            try await fixture.writer.perform(author: .capture) { context in
                _ = try context.record(.text("a", at: 4))
                _ = try context.record(.text("a again", at: 5))
            }
        }
        #expect(recopied.snapshot == CollectionSnapshot(ids: [ids[0], ids[1]], updatedIDs: [ids[0]]))

        let renamed = try await results.change {
            try await fixture.writer.perform(author: .user) { try $0.setTitle("B", of: ids[1]) }
        }
        #expect(renamed.snapshot == CollectionSnapshot(ids: [ids[0], ids[1]], updatedIDs: [ids[1]]))

        let deleted = try await results.change {
            try await fixture.writer.perform(author: .user) { try $0.delete([ids[0]]) }
        }
        #expect(deleted.snapshot == CollectionSnapshot(ids: [ids[1]]))
    }
}
