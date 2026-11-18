import Foundation
import PastoCore
import PastoFoundation
import Testing

/// Where an item is: in the history while it has a timestamp, on a pinboard while its list
/// points there, possibly both, never neither.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MembershipTests {
    private let store: StoreFixture

    init() throws {
        store = try StoreFixture()
    }

    private var history: [ItemID] {
        store.reader.itemCollection(for: .clipboard).snapshot.ids
    }

    private func items(on pinboard: ListID) -> [ItemID] {
        store.reader.itemCollection(for: pinboard).snapshot.ids
    }

    private func createPinboard(_ name: String = "Work") async throws -> ListID {
        try await store.writer.perform(author: .user) { try $0.createPinboard(name: name, color: .blue) }
    }

    private func write(_ change: @escaping @Sendable (WritingContext) throws -> Void) async throws {
        try await store.writer.perform(author: .user, change)
    }

    // MARK: - Pin

    @Test func aPinnedItemIsTheSameItemAndStaysInTheHistory() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()

        try await write { try $0.pin([ids[0]], to: pinboard) }

        #expect(items(on: pinboard) == [ids[0]])
        #expect(history == [ids[1], ids[0]])
        let pinned = try #require(store.reader.item(ids[0]))
        #expect(pinned.listID == pinboard)
        #expect(pinned.timestamp == .second(1))
        #expect(store.reader.itemCount(in: .clipboard) == 2)
        #expect(store.reader.itemCount(in: pinboard) == 1)
    }

    @Test func pinPutsEachItemFirstAndNumbersThePinboardDensely() async throws {
        let ids = try await store.record(["a", "b", "c", "d"])
        let pinboard = try await createPinboard()

        try await write { try $0.pin([ids[0]], to: pinboard) }
        // Inserted at the front one after the other: the last of the selection leads.
        try await write { try $0.pin([ids[1], ids[2], ids[3]], to: pinboard) }

        #expect(items(on: pinboard) == [ids[3], ids[2], ids[1], ids[0]])
        let orders = store.reader.items(items(on: pinboard)).map(\.displayOrderInPinboard)
        #expect(orders == [0, 1, 2, 3])
    }

    @Test func pinningAnItemThatIsAlreadyThereChangesNothing() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()
        try await write { try $0.pin(ids, to: pinboard) }

        try await write { try $0.pin([ids[0]], to: pinboard) }

        #expect(items(on: pinboard) == [ids[1], ids[0]])
    }

    @Test func pinningToAnotherPinboardMovesTheItem() async throws {
        let ids = try await store.record(["a", "b"])
        let work = try await createPinboard("Work")
        let home = try await createPinboard("Home")
        try await write { try $0.pin(ids, to: work) }

        try await write { try $0.pin([ids[1]], to: home) }

        #expect(items(on: work) == [ids[0]])
        #expect(items(on: home) == [ids[1]])
        #expect(history == [ids[1], ids[0]])
    }

    @Test func itemsCanOnlyBePinnedToAPinboard() async throws {
        let item = try await store.record(["a"])[0]

        await #expect(throws: StoreError.self) {
            try await store.writer.perform(author: .user) { try $0.pin([item], to: .clipboard) }
        }
        await #expect(throws: StoreError.listNotFound) {
            try await store.writer.perform(author: .user) { try $0.pin([item], to: ListID(rawValue: "missing")) }
        }
    }

    // MARK: - Unpin

    @Test func unpinLeavesTheItemInTheHistoryWhereItWas() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()
        try await write { try $0.pin(ids, to: pinboard) }

        try await write { try $0.unpin([ids[0]]) }

        #expect(items(on: pinboard) == [ids[1]])
        #expect(history == [ids[1], ids[0]])
        let unpinned = try #require(store.reader.item(ids[0]))
        #expect(unpinned.listID == nil)
        #expect(unpinned.timestamp == .second(1))
    }

    @Test func unpinDeletesAnItemThatWasNotInTheHistory() async throws {
        let ids = try await store.record(["a"])
        let pinboard = try await createPinboard()
        try await write { context in
            try context.pin(ids, to: pinboard)
            try context.remove(ids, from: .clipboard)
        }

        try await write { try $0.unpin(ids) }

        #expect(store.reader.item(ids[0]) == nil)
        #expect(store.reader.pasteboardItems(for: ids[0]) == nil)
    }

    // MARK: - Remove from a list

    @Test func removingFromTheHistoryDeletesWhatIsNowhereElseAndKeepsWhatIsPinned() async throws {
        let ids = try await store.record(["a", "b", "c"])
        let pinboard = try await createPinboard()
        try await write { try $0.pin([ids[0]], to: pinboard) }

        try await write { try $0.remove([ids[0], ids[1]], from: .clipboard) }

        #expect(history == [ids[2]])
        #expect(store.reader.item(ids[1]) == nil)
        #expect(items(on: pinboard) == [ids[0]])
        #expect(store.reader.item(ids[0])?.timestamp == nil)
    }

    @Test func removingFromAPinboardDeletesWhatIsNowhereElseAndKeepsWhatIsInTheHistory() async throws {
        let ids = try await store.record(["a", "b", "c"])
        let pinboard = try await createPinboard()
        try await write { context in
            try context.pin([ids[0], ids[1]], to: pinboard)
            try context.remove([ids[1]], from: .clipboard)
        }

        // "c" is not on the pinboard: it is left alone.
        try await write { try $0.remove(ids, from: pinboard) }

        #expect(items(on: pinboard).isEmpty)
        #expect(store.reader.item(ids[1]) == nil)
        // "a" is back to being a plain history item, in the place its last use gave it.
        #expect(history == [ids[2], ids[0]])
        #expect(store.reader.item(ids[0])?.listID == nil)
    }

    @Test func removingFromAnotherPinboardThanTheItemsDoesNothing() async throws {
        let ids = try await store.record(["a"])
        let work = try await createPinboard("Work")
        let home = try await createPinboard("Home")
        try await write { try $0.pin(ids, to: work) }

        try await write { try $0.remove(ids, from: home) }

        #expect(items(on: work) == ids)
    }

    @Test func deletingOutrightRemovesTheItemFromEverywhere() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()
        try await write { try $0.pin([ids[0]], to: pinboard) }

        try await write { try $0.delete([ids[0]]) }

        #expect(history == [ids[1]])
        #expect(items(on: pinboard).isEmpty)
    }

    // MARK: - Bring to the front of the history

    @Test func bringingItemsToTheHistorysFrontPutsTheFirstOneFirst() async throws {
        let ids = try await store.record(["a", "b", "c"])
        let pinboard = try await createPinboard()
        try await write { context in
            try context.pin([ids[0]], to: pinboard)
            try context.remove([ids[0]], from: .clipboard)
        }

        // What dropping cards on the history's tab does.
        try await write { context in
            var second: TimeInterval = 100
            try context.moveToFrontOfHistory([ids[0], ids[1]]) {
                second += 1
                return .second(second)
            }
        }

        // The one that only lived on the pinboard enters the history, and stays pinned.
        #expect(history == [ids[0], ids[1], ids[2]])
        #expect(items(on: pinboard) == [ids[0]])
    }

    // MARK: - Move inside a pinboard

    @Test func movingKeepsTheMovedItemsTogetherInTheirOrderBeforeTheDestination() async throws {
        let ids = try await store.record(["a", "b", "c", "d", "e"])
        let pinboard = try await createPinboard()
        // One at a time so the pinboard reads a, b, c, d, e.
        try await write { try $0.pin(ids.reversed(), to: pinboard) }
        #expect(items(on: pinboard) == ids)

        // Given in selection order; they land in the order they had on the pinboard. "x" is
        // not on the pinboard: it is ignored.
        try await write { try $0.moveItems([ids[4], ItemID(rawValue: "x"), ids[0]], toIndex: 3, in: pinboard) }

        #expect(items(on: pinboard) == [ids[1], ids[2], ids[0], ids[4], ids[3]])
        #expect(store.reader.items(items(on: pinboard)).map(\.displayOrderInPinboard) == [0, 1, 2, 3, 4])
    }

    @Test func movingToTheEnd() async throws {
        let ids = try await store.record(["a", "b", "c"])
        let pinboard = try await createPinboard()
        try await write { try $0.pin(ids.reversed(), to: pinboard) }

        try await write { try $0.moveItems([ids[0]], toIndex: 3, in: pinboard) }

        #expect(items(on: pinboard) == [ids[1], ids[2], ids[0]])
    }

    // MARK: - Capture

    @Test func copyingAgainAPinnedItemMovesItToTheFrontOfTheHistory() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()
        try await write { try $0.pin([ids[0]], to: pinboard) }

        let outcome = try await store.writer.perform(author: .capture) { try $0.record(.text("a", at: 9)) }

        #expect(outcome == RecordOutcome(id: ids[0], kind: .movedToFront, didChangeNewestItem: true))
        #expect(history == [ids[0], ids[1]])
        #expect(items(on: pinboard) == [ids[0]])
    }

    @Test func copyingAgainWhatOnlyLivesOnAPinboardBringsItIntoTheHistory() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()
        try await write { context in
            try context.pin([ids[0]], to: pinboard)
            try context.remove([ids[0]], from: .clipboard)
        }

        let outcome = try await store.writer.perform(author: .capture) { try $0.record(.text("a", at: 9)) }

        // It was not in the history: for the copy sound, it is not a copy of something there.
        #expect(outcome == RecordOutcome(id: ids[0], kind: .addedToHistory, didChangeNewestItem: true))
        #expect(history == [ids[0], ids[1]])
        #expect(items(on: pinboard) == [ids[0]])
    }
}
