import CoreData
import Foundation
import os
import PastoFoundation

/// Follows the store's persistent history and hands every consumer (search indexer, sync) the
/// transactions it has not seen yet, in order.
///
/// Each consumer has its own position, kept in `Config`, so one that was not running — or that
/// crashed half-way — resumes where it left off. Delivery is at-least-once.
public actor HistoryTailer {
    public typealias Handler = @Sendable ([HistoryTransaction]) async -> Void
    /// Called when the store no longer holds the history after a consumer's position (it was
    /// purged, or the store was replaced): what happened in between is unknown, and the consumer
    /// has to rebuild from the store as it is now.
    public typealias GapHandler = @Sendable () async -> Void

    private struct Consumer {
        let name: String
        let handler: Handler
        let onGap: GapHandler?
    }

    /// How far a consumer got.
    private struct Checkpoint: Codable, Equatable, Sendable {
        /// The archived `NSPersistentHistoryToken` of the last transaction delivered.
        var token: Data
        /// When that transaction was saved. Tokens cannot be ordered; this is what `purge` compares.
        var timestamp: Date
    }

    private let coordinator: NSPersistentStoreCoordinator
    /// Only ever runs history requests; it holds no objects.
    private let context: NSManagedObjectContext
    private let config: ConfigStore
    private let log = Log.logger(.store)

    private var consumers: [Consumer] = []
    private var tailing: Task<Void, Never>?
    /// Observes the store for as long as it is kept.
    private var observation: NotificationCenter.ObservationToken?
    /// Whether the first delivery after `start()` is over, and who waits for it.
    private var hasCaughtUp = false
    private var caughtUpWaiters: [CheckedContinuation<Void, Never>] = []

    public init(stack: PersistentStack, config: ConfigStore) {
        coordinator = stack.container.persistentStoreCoordinator
        context = stack.container.newBackgroundContext()
        self.config = config
    }

    deinit {
        tailing?.cancel()
    }

    /// Registers a consumer. `name` keys its position in `Config`: it must not change between launches.
    ///
    /// - Parameter onGap: Called instead of `handler` when the history after the consumer's
    ///   position is gone. Either way the consumer then continues from the present.
    public func addConsumer(named name: String, onGap: GapHandler? = nil, handler: @escaping Handler) {
        consumers.append(Consumer(name: name, handler: handler, onGap: onGap))
    }

    /// Moves a consumer's position to the present, for one that is about to rebuild from the
    /// store as it is now: the history before this instant will not be delivered to it.
    public func skipToPresent(consumerNamed name: String) async {
        do {
            try await setCheckpoint(currentCheckpoint(), for: Self.checkpointKey(for: name))
        } catch {
            log.error("Moving \(name, privacy: .public) to the present failed: \(error)")
        }
    }

    /// Starts delivering: first what each consumer missed while Pasto was not running, then every
    /// transaction as the store reports it.
    public func start() {
        guard tailing == nil else { return }
        // One pending wake-up is enough: each delivery reads everything that is new.
        let (wakeUps, continuation) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
        // Observing starts here, before the first read, so that no change falls in between.
        // (`NotificationCenter.messages(of:for:)` only starts observing when it is first awaited.)
        observation = NotificationCenter.default.addObserver(of: coordinator, for: .remoteChange) { _ in
            continuation.yield()
        }
        continuation.yield()
        tailing = Task { [weak self] in
            for await _ in wakeUps {
                await self?.deliverPending()
                await self?.didCatchUp()
            }
        }
    }

    public func stop() {
        tailing?.cancel()
        tailing = nil
        observation = nil
    }

    /// Returns once the first delivery after `start()` — what the consumers missed while Pasto
    /// was not running — is over: from then on, purging can take everything older than the
    /// window it is given.
    public func waitUntilCaughtUp() async {
        guard !hasCaughtUp else { return }
        await withCheckedContinuation { caughtUpWaiters.append($0) }
    }

    private func didCatchUp() {
        guard !hasCaughtUp else { return }
        hasCaughtUp = true
        caughtUpWaiters.forEach { $0.resume() }
        caughtUpWaiters = []
    }

    /// Deletes the history older than `date`, except what some consumer has not been given yet.
    public func purge(before date: Date) async throws {
        let checkpoints = consumers.map { config.value(for: Self.checkpointKey(for: $0.name)).value }
        // A consumer that has seen nothing still needs everything.
        guard !checkpoints.contains(nil) else { return }
        let cutoff = checkpoints.compactMap { $0?.timestamp }.reduce(date, min)
        try await context.perform { [context] in
            _ = try context.execute(NSPersistentHistoryChangeRequest.deleteHistory(before: cutoff))
        }
    }

    // MARK: - Delivery

    private static func checkpointKey(for consumer: String) -> ConfigKey<JSONConfigValue<Checkpoint?>> {
        ConfigKey("historyTailer.checkpoint.\(consumer)", default: JSONConfigValue(nil))
    }

    private func deliverPending() async {
        for consumer in consumers {
            let key = Self.checkpointKey(for: consumer.name)
            do {
                let pending = try await transactions(after: config.value(for: key).value)
                guard let checkpoint = pending.checkpoint else { continue }
                if !pending.transactions.isEmpty {
                    await consumer.handler(pending.transactions)
                }
                // Moved only once the consumer is done: a crash in between repeats the batch
                // instead of losing it.
                config.set(JSONConfigValue(checkpoint), for: key)
            } catch where Self.isGap(error) {
                log.error("The store no longer holds the history \(consumer.name, privacy: .public) was at: \(error)")
                // Taken before the consumer rebuilds: what changes meanwhile is delivered afterwards.
                let present = try? await currentCheckpoint()
                await consumer.onGap?()
                setCheckpoint(present, for: key)
            } catch {
                log.error("Reading history for \(consumer.name, privacy: .public) failed: \(error)")
            }
        }
    }

    /// The codes Core Data reports a history position that no longer exists with. The second one
    /// has no public name.
    private static let gapErrorCodes = [NSPersistentHistoryTokenExpiredError, 134_501]

    private static func isGap(_ error: any Error) -> Bool {
        let error = error as NSError
        return error.domain == NSCocoaErrorDomain && gapErrorCodes.contains(error.code)
    }

    private func setCheckpoint(_ checkpoint: Checkpoint?, for key: ConfigKey<JSONConfigValue<Checkpoint?>>) {
        if let checkpoint {
            config.set(JSONConfigValue(checkpoint), for: key)
        } else {
            config.reset(key)
        }
    }

    /// The position after everything saved so far; `nil` for a store with no history at all.
    private func currentCheckpoint() async throws -> Checkpoint? {
        try await context.perform { [coordinator] in
            guard let token = coordinator.currentPersistentHistoryToken(fromStores: nil) else { return nil }
            return Checkpoint(
                token: try NSKeyedArchiver.archivedData(withRootObject: token, requiringSecureCoding: true),
                timestamp: Date()
            )
        }
    }

    /// The transactions saved after `checkpoint` that touched items, and the position after them
    /// (`nil` when there is nothing new at all).
    private func transactions(after checkpoint: Checkpoint?) async throws -> (transactions: [HistoryTransaction], checkpoint: Checkpoint?) {
        try await context.perform { [context] in
            let token = try checkpoint.flatMap {
                try NSKeyedUnarchiver.unarchivedObject(ofClass: NSPersistentHistoryToken.self, from: $0.token)
            }
            let request = NSPersistentHistoryChangeRequest.fetchHistory(after: token)
            request.resultType = .transactionsAndChanges
            let result = try context.execute(request) as? NSPersistentHistoryResult
            let history = result?.result as? [NSPersistentHistoryTransaction] ?? []
            guard let last = history.last else { return ([], nil) }

            let itemChanges = history.map { transaction in
                (transaction.changes ?? []).filter { $0.changedObjectID.entity.name == ItemEntity.entityName }
            }
            let identifiers = try Self.identifiers(for: itemChanges.joined(), in: context)

            let transactions = zip(history, itemChanges).compactMap { transaction, changes -> HistoryTransaction? in
                let changes = changes.compactMap { change -> HistoryTransaction.ItemChange? in
                    guard let identifier = identifiers[change.changedObjectID] else { return nil }
                    let kind: HistoryTransaction.ItemChange.Kind = switch change.changeType {
                    case .insert: .inserted
                    case .update: .updated
                    case .delete: .deleted
                    @unknown default: .updated
                    }
                    return HistoryTransaction.ItemChange(id: ItemID(rawValue: identifier), kind: kind)
                }
                guard !changes.isEmpty else { return nil }
                return HistoryTransaction(author: transaction.author.flatMap(TransactionAuthor.init), changes: changes)
            }

            let checkpoint = Checkpoint(
                token: try NSKeyedArchiver.archivedData(withRootObject: last.token, requiringSecureCoding: true),
                timestamp: last.timestamp
            )
            return (transactions, checkpoint)
        }
    }

    /// History identifies objects by `NSManagedObjectID`; consumers know items by `identifier`.
    /// Live items are looked up; deleted ones left theirs in the tombstone. An item deleted after
    /// these transactions is missing from the result: its changes are dropped, which is right,
    /// because the deletion that follows is all a consumer needs to hear about it.
    private static func identifiers(
        for changes: some Sequence<NSPersistentHistoryChange>,
        in context: NSManagedObjectContext
    ) throws -> [NSManagedObjectID: String] {
        var identifiers: [NSManagedObjectID: String] = [:]
        var live: Set<NSManagedObjectID> = []
        for change in changes {
            if change.changeType == .delete {
                identifiers[change.changedObjectID] = change.tombstone?["identifier"] as? String
            } else {
                live.insert(change.changedObjectID)
            }
        }

        let request = ItemEntity.makeRequest(NSPredicate(format: "self IN %@", Array(live)))
        request.propertiesToFetch = ["identifier"]
        for item in try context.fetch(request) {
            identifiers[item.objectID] = item.identifier
        }
        context.reset()
        return identifiers
    }
}
