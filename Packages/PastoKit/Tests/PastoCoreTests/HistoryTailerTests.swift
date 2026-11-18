import Foundation
import PastoCore
import PastoFoundation
import Testing

@Suite(.timeLimit(.minutes(1)))
struct HistoryTailerTests {
    @Test func deliversEveryTransactionWithItsAuthor() async throws {
        let ephemeral = EphemeralDefaults()
        let stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        let writer = StoreWriter(stack: stack)
        let tailer = HistoryTailer(stack: stack, config: ConfigStore(defaults: ephemeral.defaults))

        let (delivered, continuation) = AsyncStream.makeStream(of: HistoryTransaction.self)
        await tailer.addConsumer(named: "test") { transactions in
            transactions.forEach { continuation.yield($0) }
        }
        await tailer.start()
        var transactions = delivered.makeAsyncIterator()

        let id = try await writer.perform(author: .capture) { try $0.record(.text("a", at: 1)).id }
        #expect(await transactions.next() == HistoryTransaction(author: .capture, changes: [.init(id: id, kind: .inserted)]))

        try await writer.perform(author: .user) { try $0.setTitle("A", of: id) }
        #expect(await transactions.next() == HistoryTransaction(author: .user, changes: [.init(id: id, kind: .updated)]))

        // The item is gone by the time the deletion is read: its identifier comes from the tombstone.
        _ = try await writer.perform(author: .maintenance) { try $0.eraseHistory() }
        #expect(await transactions.next() == HistoryTransaction(author: .maintenance, changes: [.init(id: id, kind: .deleted)]))

        await tailer.stop()
    }

    @Test func aPositionTheStoreNoLongerHoldsIsReportedAsAGapAndMovesToThePresent() async throws {
        let ephemeral = EphemeralDefaults()
        let config = ConfigStore(defaults: ephemeral.defaults)
        let (deliveries, continuation) = AsyncStream.makeStream(of: String.self)
        var delivered = deliveries.makeAsyncIterator()

        // The consumer gets as far as the first store's only item…
        let replaced = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        let first = HistoryTailer(stack: replaced, config: config)
        await first.addConsumer(named: "test") { _ in continuation.yield("transactions") }
        await first.start()
        _ = try await StoreWriter(stack: replaced).perform(author: .capture) { try $0.record(.text("a", at: 1)) }
        #expect(await delivered.next() == "transactions")
        await first.stop()

        // …and is then pointed at another store, which knows nothing of that position.
        let stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        let writer = StoreWriter(stack: stack)
        _ = try await writer.perform(author: .capture) { try $0.record(.text("b", at: 2)) }
        let tailer = HistoryTailer(stack: stack, config: config)
        await tailer.addConsumer(named: "test", onGap: { continuation.yield("gap") }) { _ in
            continuation.yield("transactions")
        }
        await tailer.start()
        #expect(await delivered.next() == "gap")

        // From the gap on it follows the new store: only what is saved afterwards arrives.
        _ = try await writer.perform(author: .capture) { try $0.record(.text("c", at: 3)) }
        #expect(await delivered.next() == "transactions")
        await tailer.stop()
    }

    @Test func skippingToThePresentLeavesEarlierHistoryUndelivered() async throws {
        let ephemeral = EphemeralDefaults()
        let stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        let writer = StoreWriter(stack: stack)
        let tailer = HistoryTailer(stack: stack, config: ConfigStore(defaults: ephemeral.defaults))
        let (delivered, continuation) = AsyncStream.makeStream(of: HistoryTransaction.self)
        await tailer.addConsumer(named: "test") { transactions in
            transactions.forEach { continuation.yield($0) }
        }

        _ = try await writer.perform(author: .capture) { try $0.record(.text("before", at: 1)) }
        await tailer.skipToPresent(consumerNamed: "test")
        await tailer.start()
        let id = try await writer.perform(author: .capture) { try $0.record(.text("after", at: 2)).id }

        var transactions = delivered.makeAsyncIterator()
        #expect(await transactions.next() == HistoryTransaction(author: .capture, changes: [.init(id: id, kind: .inserted)]))
        await tailer.stop()
    }

    /// What store maintenance relies on: it waits for the first delivery, and then a purge takes
    /// what every consumer has been given and nothing else.
    @Test func purgingAfterCatchingUpKeepsOnlyWhatAConsumerHasNotSeen() async throws {
        let ephemeral = EphemeralDefaults()
        let config = ConfigStore(defaults: ephemeral.defaults)
        let stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        let writer = StoreWriter(stack: stack)
        _ = try await writer.perform(author: .capture) { try $0.record(.text("seen", at: 1)) }

        let tailer = HistoryTailer(stack: stack, config: config)
        await tailer.addConsumer(named: "test") { _ in }
        await tailer.start()
        await tailer.waitUntilCaughtUp()
        // Already caught up: returns at once.
        await tailer.waitUntilCaughtUp()
        await tailer.stop()

        // Saved after the consumer stopped: it has not seen this one.
        let unseen = try await writer.perform(author: .capture) { try $0.record(.text("unseen", at: 2)).id }
        try await tailer.purge(before: Date.distantFuture)

        let (delivered, continuation) = AsyncStream.makeStream(of: HistoryTransaction.self)
        let resumed = HistoryTailer(stack: stack, config: config)
        await resumed.addConsumer(named: "test") { transactions in transactions.forEach { continuation.yield($0) } }
        await resumed.start()
        var transactions = delivered.makeAsyncIterator()
        #expect(await transactions.next() == HistoryTransaction(author: .capture, changes: [.init(id: unseen, kind: .inserted)]))
        await resumed.stop()
    }
}
