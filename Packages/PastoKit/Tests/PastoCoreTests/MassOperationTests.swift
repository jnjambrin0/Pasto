import CoreData
import Foundation
@testable import PastoCore
import PastoFoundation
import Testing

/// Erasing the history and retention go a batch of items at a time when there are many, and in
/// one transaction when there are few or the transaction has to be reversible. A batch of three
/// here, of 500 in the app.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct MassOperationTests {
    private let stack: PersistentStack
    private let reader: StoreReader
    private let writer: StoreWriter

    init() throws {
        stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        reader = StoreReader(stack: stack)
        writer = StoreWriter(stack: stack, now: { StoreFixture.now }, batchSize: 3)
    }

    /// Ten items copied at seconds 1…10; the two oldest are pinned.
    private func recordTenAndPinTheTwoOldest() async throws -> [ItemID] {
        let items = try await writer.perform(author: .capture) { context in
            try (1...10).map { try context.record(.text("item \($0)", at: TimeInterval($0))).id }
        }
        try await writer.perform(author: .user) { context in
            try context.pin(Array(items.prefix(2)), to: try context.createPinboard(name: "Work", color: .blue))
        }
        return items
    }

    /// The transactions saved after `token`, by author.
    private func transactions(after token: NSPersistentHistoryToken?) async throws -> [String?] {
        let context = stack.container.newBackgroundContext()
        return try await context.perform {
            let result = try context.execute(NSPersistentHistoryChangeRequest.fetchHistory(after: token)) as? NSPersistentHistoryResult
            return (result?.result as? [NSPersistentHistoryTransaction] ?? []).map(\.author)
        }
    }

    private var currentToken: NSPersistentHistoryToken? {
        stack.container.persistentStoreCoordinator.currentPersistentHistoryToken(fromStores: nil)
    }

    private func count(_ entity: String) throws -> Int {
        try stack.container.viewContext.count(for: NSFetchRequest<NSManagedObject>(entityName: entity))
    }

    /// Waits until the collection shows `expected`, however many snapshots that takes.
    private func waitFor(_ expected: [ItemID], in collection: ItemCollection) async {
        guard collection.snapshot.ids != expected else { return }
        let (snapshots, continuation) = AsyncStream.makeStream(of: CollectionSnapshot<ItemID>.self)
        collection.onChange = { continuation.yield($0) }
        defer { collection.onChange = nil }
        for await snapshot in snapshots where snapshot.ids == expected { return }
    }

    @Test func retentionOverSeveralBatchesDeletesWhatExpiredWithItsDataAndSparesPinnedItems() async throws {
        let items = try await recordTenAndPinTheTwoOldest()
        let history = reader.itemCollection(for: .clipboard)
        let token = currentToken

        let deleted = try await writer.perform(author: .maintenance) { try $0.deleteHistory(olderThan: .second(8)) }

        // Seconds 3…7 expired; the pinned ones at 1 and 2 never do.
        #expect(deleted == 5)
        #expect(reader.totalItemCount() == 5)
        #expect(try count(ItemDataEntity.entityName) == 5)
        // Two batches of three: the first saved on its own, the second with the transaction.
        #expect(try await transactions(after: token) == ["maintenance", "maintenance"])
        // The view context heard of every deletion.
        await waitFor([items[9], items[8], items[7], items[1], items[0]], in: history)
    }

    @Test func erasingOverSeveralBatchesEmptiesTheHistoryAndKeepsPinnedItems() async throws {
        let items = try await recordTenAndPinTheTwoOldest()
        let history = reader.itemCollection(for: .clipboard)

        let removed = try await writer.perform(author: .user) { try $0.eraseHistory() }

        #expect(removed == 10)
        await waitFor([], in: history)
        #expect(reader.items(items).map(\.id) == [items[0], items[1]])
        #expect(reader.items(items).allSatisfy { $0.timestamp == nil && $0.listID != nil })
        #expect(try count(ItemDataEntity.entityName) == 2)
    }

    @Test func aFewExpiredItemsExpireInTheTransactionOfTheCapture() async throws {
        _ = try await writer.perform(author: .capture) { context in
            try (1...4).map { try context.record(.text("item \($0)", at: TimeInterval($0))).id }
        }
        let token = currentToken

        let deleted = try await writer.perform(author: .capture) { context in
            _ = try context.record(.text("new", at: 20))
            return try context.deleteHistory(olderThan: .second(3))
        }

        #expect(deleted == 2)
        #expect(try await transactions(after: token) == ["capture"])
    }

    @Test func aReversibleTransactionStaysOneAndItsReversalBringsEverythingBack() async throws {
        _ = try await writer.perform(author: .capture) { context in
            try (1...8).map { try context.record(.text("item \($0)", at: TimeInterval($0))).id }
        }
        let token = currentToken

        let (deleted, reversal) = try await writer.performReversibly(author: .user) { try $0.deleteHistory(olderThan: .second(8)) }

        #expect(deleted == 7)
        #expect(try await transactions(after: token) == ["user"])
        try await writer.perform(author: .user) { try $0.apply(reversal) }
        #expect(reader.totalItemCount() == 8)
    }

    @Test func theWriterHoldsNoObjectsBetweenTransactions() async throws {
        _ = try await recordTenAndPinTheTwoOldest()
        _ = try await writer.perform(author: .user) { try $0.eraseHistory() }

        let context = writer.context
        #expect(await context.perform { context.registeredObjects.isEmpty })
    }
}
