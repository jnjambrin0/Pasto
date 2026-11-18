import CoreData
import Foundation
import os
import PastoFoundation

/// The only way to change the store: every write runs, one at a time, on a single background
/// context. The view context picks the result up by merging.
public final class StoreWriter: Sendable {
    /// What a round of maintenance did.
    public struct MaintenanceReport: Sendable, Equatable {
        /// Bytes the database file gave back to the disk.
        public var bytesReclaimed: Int64
        /// Whether the database was rebuilt to be able to reclaim space from then on.
        public var vacuumed: Bool
    }

    /// A transaction that deletes at least this many items gives their space back right after.
    static var compactionThreshold: Int { 1_000 }

    let context: NSManagedObjectContext
    private let localDeviceIdentifier: String
    private let now: @Sendable () -> Date
    private let batchSize: Int
    /// The database file; `nil` for a store in memory.
    private let databaseURL: URL?
    private let log = Log.logger(.store)

    /// - Parameter now: The clock that stamps `createdAt` and `updatedAt`.
    public convenience init(stack: PersistentStack, now: @escaping @Sendable () -> Date = { Date() }) {
        self.init(stack: stack, now: now, batchSize: 500)
    }

    /// - Parameter batchSize: The most items a mass operation handles per save.
    init(stack: PersistentStack, now: @escaping @Sendable () -> Date, batchSize: Int) {
        context = stack.container.newBackgroundContext()
        // Uniqueness conflicts resolve in favour of what is being written.
        context.mergePolicy = NSMergePolicy.mergeByPropertyObjectTrump
        localDeviceIdentifier = stack.localDeviceIdentifier
        self.now = now
        self.batchSize = batchSize
        let url = stack.container.persistentStoreCoordinator.persistentStores.first?.url
        databaseURL = url?.path == "/dev/null" ? nil : url
    }

    /// Runs `work` as one transaction: saved if it changed anything, rolled back if it throws.
    ///
    /// A mass operation inside it — erasing the history, a retention that lets many items expire —
    /// may save in several transactions, a batch of items at a time.
    public func perform<T: Sendable>(
        author: TransactionAuthor,
        _ work: @escaping @Sendable (WritingContext) throws -> T
    ) async throws -> T {
        try await run(author: author, savesInBatches: true, work)
    }

    /// Runs `work` as one transaction, like `perform`, and also returns what would undo what it
    /// did to the items. Always a single transaction, however many items it touches.
    public func performReversibly<T: Sendable>(
        author: TransactionAuthor,
        _ work: @escaping @Sendable (WritingContext) throws -> T
    ) async throws -> (result: T, reversal: ItemChangeReversal) {
        try await run(author: author, savesInBatches: false) { context in
            let result = try work(context)
            return (result, context.reversalOfPendingChanges())
        }
    }

    /// Gives back to the disk the space the store no longer uses, and empties the write-ahead
    /// log: once a day, and after the persistent history is purged. Runs between transactions,
    /// never during one. `nil` for a store in memory.
    @discardableResult
    public func performMaintenance() async throws -> MaintenanceReport? {
        guard let databaseURL else { return nil }
        return try await context.perform { [log] in
            let report = try StoreCompaction.compact(databaseAt: databaseURL)
            log.info("Store maintenance reclaimed \(report.bytesReclaimed) bytes\(report.vacuumed ? " (rebuilt)" : "")")
            return MaintenanceReport(bytesReclaimed: report.bytesReclaimed, vacuumed: report.vacuumed)
        }
    }

    private func run<T: Sendable>(
        author: TransactionAuthor,
        savesInBatches: Bool,
        _ work: @escaping @Sendable (WritingContext) throws -> T
    ) async throws -> T {
        try await context.perform { [self, context, localDeviceIdentifier, now, batchSize, databaseURL, log] in
            context.transactionAuthor = author.rawValue
            defer {
                context.transactionAuthor = nil
                // Nothing a transaction loaded outlives it: no managed object leaves `perform`,
                // and a context that kept them would grow with every write.
                context.reset()
            }
            let tally = WriteTally()
            let result: T
            do {
                let writing = WritingContext(
                    context: context,
                    now: now(),
                    localDeviceIdentifier: localDeviceIdentifier,
                    batchSize: batchSize,
                    savesInBatches: savesInBatches,
                    tally: tally
                )
                result = try work(writing)
                if context.hasChanges {
                    writing.tallyPendingDeletions()
                    try context.save()
                    self.report(.saved)
                }
            } catch {
                // Whatever the cause — a full disk included — the context is left as it was
                // before the transaction, ready for the next one.
                context.rollback()
                if WriteOutcome.isFailureToSave(error) { self.report(.failed) }
                throw error
            }
            if tally.deletedItems >= Self.compactionThreshold, let databaseURL {
                do {
                    let report = try StoreCompaction.compact(databaseAt: databaseURL)
                    log.info("Reclaimed \(report.bytesReclaimed) bytes after deleting \(tally.deletedItems) items")
                } catch {
                    log.error("\(error)")
                }
            }
            return result
        }
    }

    // MARK: - Outcomes

    private static let outcomeNotification = Notification.Name("jnjambrino.Pasto.StoreWriter.outcome")
    private static let outcomeKey = "outcome"

    /// What becomes of the writes from now on, whoever makes them — captures, the panel, the
    /// settings: `.saved` for every transaction that saved its changes, `.failed` for one the
    /// store could not take. Nothing for one that changed nothing, nor for one rejected for what
    /// it asked (`StoreError`). Delivered on the writer's queue.
    public func outcomes() -> AsyncStream<WriteOutcome> {
        let (stream, continuation) = AsyncStream.makeStream(of: WriteOutcome.self)
        // The token only ever goes back to `NotificationCenter`, which is thread-safe.
        nonisolated(unsafe) let observer = NotificationCenter.default.addObserver(
            forName: Self.outcomeNotification,
            object: self,
            queue: nil
        ) { notification in
            if let outcome = notification.userInfo?[Self.outcomeKey] as? WriteOutcome {
                continuation.yield(outcome)
            }
        }
        continuation.onTermination = { _ in NotificationCenter.default.removeObserver(observer) }
        return stream
    }

    private func report(_ outcome: WriteOutcome) {
        NotificationCenter.default.post(name: Self.outcomeNotification, object: self, userInfo: [Self.outcomeKey: outcome])
    }
}
