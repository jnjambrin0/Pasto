import Foundation
import PastoCore
import PastoFoundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct PinboardTests {
    private let store: StoreFixture

    init() throws {
        store = try StoreFixture()
    }

    private func createPinboards(_ names: [String]) async throws -> [ListID] {
        try await store.writer.perform(author: .user) { context in
            try names.map { try context.createPinboard(name: $0, color: .blue) }
        }
    }

    // MARK: - Lists

    @Test func aNewStoreHasOnlyTheClipboardHistory() throws {
        #expect(store.reader.lists() == [
            ClipList(id: .clipboard, name: "", type: .clipboard, attributes: .clipboard(capacity: .month), index: 0),
        ])
    }

    @Test func createPinboardAddsItAfterTheOtherLists() async throws {
        let ids = try await store.writer.perform(author: .user) { context in
            [try context.createPinboard(name: "Work", color: .green), try context.createPinboard(name: "Home", color: .pink)]
        }

        #expect(store.reader.lists().dropFirst() == [
            ClipList(id: ids[0], name: "Work", type: .pinboard, attributes: .pinboard(color: .green), index: 1),
            ClipList(id: ids[1], name: "Home", type: .pinboard, attributes: .pinboard(color: .pink), index: 2),
        ])
    }

    @Test func renameAndRecolor() async throws {
        let id = try await createPinboards(["Work"])[0]

        try await store.writer.perform(author: .user) { context in
            try context.renameList(id, to: "Office")
            try context.setPinboardColor(.orange, of: id)
        }

        let list = try #require(store.reader.list(id))
        #expect(list.name == "Office")
        #expect(list.attributes == .pinboard(color: .orange))
    }

    @Test func reorderListsPutsTheMentionedOnesFirst() async throws {
        let ids = try await createPinboards(["A", "B", "C"])

        try await store.writer.perform(author: .user) { try $0.reorderLists([.clipboard, ids[2], ids[0]]) }

        #expect(store.reader.lists().map(\.id) == [.clipboard, ids[2], ids[0], ids[1]])
        #expect(store.reader.lists().map(\.index) == [0, 1, 2, 3])
    }

    @Test func deleteListDeletesOnlyTheItemsThatLivedOnItAlone() async throws {
        let items = try await store.record(["a", "b", "c", "d"])
        let pinboards = try await createPinboards(["Work", "Home"])
        try await store.writer.perform(author: .user) { context in
            try context.pin([items[0], items[1], items[2]], to: pinboards[0])
            try context.pin([items[3]], to: pinboards[1])
            // "a" now lives on the pinboard alone; "b" and "c" are in the history too.
            try context.remove([items[0]], from: .clipboard)
        }

        try await store.writer.perform(author: .user) { try $0.deleteList(pinboards[0]) }

        #expect(store.reader.lists().map(\.id) == [.clipboard, pinboards[1]])
        #expect(store.reader.item(items[0]) == nil)
        #expect(store.reader.pasteboardItems(for: items[0]) == nil)
        // The others keep their place in the history and lose the pinboard.
        #expect(store.reader.itemCollection(for: .clipboard).snapshot.ids == [items[3], items[2], items[1]])
        #expect(store.reader.items([items[1], items[2]]).allSatisfy { $0.listID == nil })
        #expect(store.reader.item(items[3])?.listID == pinboards[1])
    }

    @Test func theClipboardHistoryCannotBeDeleted() async throws {
        await #expect(throws: StoreError.cannotDeleteClipboardHistory) {
            try await store.writer.perform(author: .user) { try $0.deleteList(.clipboard) }
        }
        await #expect(throws: StoreError.listNotFound) {
            try await store.writer.perform(author: .user) { try $0.deleteList(ListID(rawValue: "missing")) }
        }
        #expect(store.reader.lists().map(\.id) == [.clipboard])
    }

    // MARK: - Items on pinboards

    // The rules of where an item is — history, pinboard or both — are in `MembershipTests`.

    @Test func itemsCanOnlyBePinnedToAPinboard() async throws {
        let item = try await store.record(["a"])[0]

        await #expect(throws: StoreError.self) {
            try await store.writer.perform(author: .user) { try $0.pin([item], to: .clipboard) }
        }
        await #expect(throws: StoreError.listNotFound) {
            try await store.writer.perform(author: .user) { try $0.pin([item], to: ListID(rawValue: "missing")) }
        }
    }
}
