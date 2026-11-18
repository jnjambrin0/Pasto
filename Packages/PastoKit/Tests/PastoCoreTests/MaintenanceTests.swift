import Foundation
import PastoCore
import PastoFoundation
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MaintenanceTests {
    private let store: StoreFixture

    init() throws {
        store = try StoreFixture()
    }

    /// Items copied at seconds 1, 2, 3 and 4; the oldest one is pinned.
    private func recordFourAndPinTheOldest() async throws -> [ItemID] {
        let items = try await store.record(["a", "b", "c", "d"])
        try await store.writer.perform(author: .user) { context in
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.pin([items[0]], to: pinboard)
        }
        return items
    }

    @Test func deleteHistoryOlderThanADateSparesPinnedItems() async throws {
        let items = try await recordFourAndPinTheOldest()

        let deleted = try await store.writer.perform(author: .maintenance) { try $0.deleteHistory(olderThan: .second(3)) }

        #expect(deleted == 1)
        // The pinned item is older than the cutoff too, and keeps its place in the history.
        #expect(store.reader.itemCollection(for: .clipboard).snapshot.ids == [items[3], items[2], items[0]])
    }

    @Test func eraseHistoryEmptiesItAndDeletesWhatIsNotPinned() async throws {
        let items = try await recordFourAndPinTheOldest()

        let removed = try await store.writer.perform(author: .user) { try $0.eraseHistory() }

        #expect(removed == 4)
        #expect(store.reader.itemCollection(for: .clipboard).snapshot.ids.isEmpty)
        #expect(store.reader.items(items).map(\.id) == [items[0]])
        let pinned = try #require(store.reader.item(items[0]))
        #expect(pinned.timestamp == nil)
        #expect(pinned.listID != nil)
    }

    @Test func loweringTheCapacityDeletesWhatExpiresAndSparesPinnedItems() async throws {
        let items = try await recordFourAndPinTheOldest()
        // The writer's clock is `StoreFixture.now`; the items were copied in its first seconds.
        #expect(store.reader.historyCapacity == .month)
        #expect(store.reader.expiredHistoryItemCount(for: .day, at: StoreFixture.now) == 3)
        #expect(store.reader.expiredHistoryItemCount(for: .unlimited, at: StoreFixture.now) == 0)

        let deleted = try await store.writer.perform(author: .user) { try $0.setHistoryCapacity(.day) }

        #expect(deleted == 3)
        #expect(store.reader.totalItemCount() == 1)
        #expect(store.reader.item(items[0]) != nil)
    }

    @Test func raisingTheCapacityDeletesNothing() async throws {
        _ = try await recordFourAndPinTheOldest()

        let deleted = try await store.writer.perform(author: .user) { try $0.setHistoryCapacity(HistoryCapacity(days: 60)) }

        #expect(deleted == 0)
        #expect(store.reader.totalItemCount() == 4)
    }
}
