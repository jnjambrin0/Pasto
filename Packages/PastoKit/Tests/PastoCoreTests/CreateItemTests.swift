import Foundation
import PastoCore
import PastoFoundation
import Testing

/// "New Text Item": the item goes to the front of the list on show, and on a pinboard it does
/// not enter the history.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct CreateItemTests {
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

    private func createPinboard() async throws -> ListID {
        try await store.writer.perform(author: .user) { try $0.createPinboard(name: "Work", color: .blue) }
    }

    private func create(_ text: String, at second: TimeInterval, in list: ListID) async throws -> ItemID {
        try await store.writer.perform(author: .user) { try $0.create(.text(text, at: second), in: list) }
    }

    @Test func inTheHistoryTheItemGoesFirst() async throws {
        let ids = try await store.record(["a", "b"])

        let id = try await create("new", at: 10, in: .clipboard)

        #expect(history == [id, ids[1], ids[0]])
        #expect(store.reader.item(id)?.timestamp == .second(10))
        #expect(store.reader.item(id)?.listID == nil)
    }

    @Test func inTheHistoryContentAlreadyThereMovesToTheFrontWithoutACopy() async throws {
        let ids = try await store.record(["a", "b"])

        let id = try await create("a", at: 10, in: .clipboard)

        #expect(id == ids[0])
        #expect(history == [ids[0], ids[1]])
        #expect(store.reader.itemCount(in: .clipboard) == 2)
    }

    @Test func onAPinboardTheItemGoesFirstAndStaysOutOfTheHistory() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()
        try await store.writer.perform(author: .user) { try $0.pin([ids[0]], to: pinboard) }

        let id = try await create("new", at: 10, in: pinboard)

        #expect(items(on: pinboard) == [id, ids[0]])
        #expect(history == [ids[1], ids[0]])
        let item = try #require(store.reader.item(id))
        #expect(item.timestamp == nil)
        #expect(item.listID == pinboard)
        #expect(item.createdAt == StoreFixture.now)
        #expect(item.device?.name == "Test Mac")
    }

    @Test func onAPinboardContentInTheHistoryIsPinnedWithoutMovingInTheHistory() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await createPinboard()

        let id = try await create("a", at: 10, in: pinboard)

        #expect(id == ids[0])
        #expect(items(on: pinboard) == [ids[0]])
        #expect(history == [ids[1], ids[0]])
        #expect(store.reader.item(id)?.timestamp == .second(1))
        #expect(store.reader.itemCount(in: .clipboard) == 2)
    }

    @Test func onAPinboardContentAlreadyOnItKeepsItsPlace() async throws {
        let pinboard = try await createPinboard()
        let first = try await create("a", at: 1, in: pinboard)
        let second = try await create("b", at: 2, in: pinboard)

        let again = try await create("a", at: 3, in: pinboard)

        #expect(again == first)
        #expect(items(on: pinboard) == [second, first])
        #expect(history.isEmpty)
    }

    @Test func aPinboardThatIsGoneMeansTheHistory() async throws {
        let id = try await create("new", at: 10, in: ListID(rawValue: "gone"))

        #expect(history == [id])
        #expect(store.reader.item(id)?.listID == nil)
    }
}
