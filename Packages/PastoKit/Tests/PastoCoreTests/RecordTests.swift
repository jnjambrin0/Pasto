import Foundation
import PastoCore
import PastoFoundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct RecordTests {
    private let store: StoreFixture
    private let safari = SourceApplication(bundleIdentifier: "com.apple.Safari", name: "Safari")

    init() throws {
        store = try StoreFixture()
    }

    @Test func insertsNewContentIntoTheHistory() async throws {
        let outcome = try await store.writer.perform(author: .capture) { [safari] in
            try $0.record(.text("hello", at: 10, from: safari))
        }

        #expect(outcome.kind == .inserted)
        let item = try #require(store.reader.item(outcome.id))
        #expect(item.type == .text)
        #expect(item.preview == .text(TextPreview(text: "hello", characterCount: 5)))
        #expect(item.timestamp == .second(10))
        #expect(item.createdAt == StoreFixture.now)
        #expect(item.title == nil)
        #expect(item.listID == nil)
        #expect(item.sourceApplication == safari)
        #expect(item.device?.name == "Test Mac")
        #expect(item.device?.type == .mac)
        #expect(item.device?.appVersion == "1.0")
        #expect(store.reader.pasteboardItems(for: outcome.id) == NewItem.text("hello", at: 10).pasteboardItems)
        #expect(store.reader.itemCount(in: .clipboard) == 1)
    }

    @Test func movesContentItAlreadyHasToTheFront() async throws {
        let history = store.reader.itemCollection(for: .clipboard)
        let ids = try await history.change { try await store.record(["a", "b"]) }.result
        #expect(history.snapshot.ids == [ids[1], ids[0]])

        let xcode = SourceApplication(bundleIdentifier: "com.apple.dt.Xcode", name: "Xcode")
        let change = try await history.change {
            try await store.writer.perform(author: .capture) { try $0.record(.text("a", at: 30, from: xcode)) }
        }

        #expect(change.result == RecordOutcome(id: ids[0], kind: .movedToFront, didChangeNewestItem: true))
        #expect(change.snapshot == CollectionSnapshot(ids: [ids[0], ids[1]], updatedIDs: [ids[0]]))
        let item = try #require(store.reader.item(ids[0]))
        #expect(item.timestamp == .second(30))
        #expect(item.sourceApplication == xcode)
        #expect(store.reader.itemCount(in: .clipboard) == 2)
    }

    @Test func aCopyWithoutASourceLeavesTheItemWithoutOne() async throws {
        let id = try await store.writer.perform(author: .capture) { [safari] in
            try $0.record(.text("a", at: 1, from: safari)).id
        }

        try await store.writer.perform(author: .capture) { _ = try $0.record(.text("a", at: 2)) }

        let item = try #require(store.reader.item(id))
        #expect(item.sourceApplication == nil)
        // The device is the one that made the item.
        #expect(item.device?.name == "Test Mac")
    }

    @Test func keepsOneApplicationPerBundleIdentifier() async throws {
        let icon = Data([1, 2, 3])
        let ids = try await store.writer.perform(author: .capture) { [safari] context in
            let first = try context.record(.text("a", at: 1, from: safari)).id
            // What is computed later (color, icon) must survive captures that do not carry it.
            try context.upsertApplication(SourceApplication(
                bundleIdentifier: safari.bundleIdentifier, name: safari.name, colorCode: 0x1E90FF, iconData: icon
            ))
            let renamed = SourceApplication(bundleIdentifier: safari.bundleIdentifier, name: "Safari Technology Preview")
            let second = try context.record(.text("b", at: 2, from: renamed)).id
            return [first, second]
        }

        let expected = SourceApplication(
            bundleIdentifier: "com.apple.Safari", name: "Safari Technology Preview", colorCode: 0x1E90FF, iconData: icon
        )
        #expect(store.reader.items(ids).map(\.sourceApplication) == [expected, expected])
    }
}
