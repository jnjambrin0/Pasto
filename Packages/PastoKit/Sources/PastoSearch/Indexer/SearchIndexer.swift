import Foundation
import os
import PastoCore
import PastoFoundation
import PastoRecognition

/// Keeps the search index in step with the store: indexes everything once, in batches it can
/// resume, then follows the store's changes, and reads the text of images in the background.
public actor SearchIndexer {
    /// Batch size, retries, timeouts and pauses.
    enum Metrics {
        static let batchLimit = 100
        /// Tries per index write, the first included.
        static let maxAttempts = 3
        /// Wait before the first retry; it doubles with every further one.
        static let retryBaseDelay = Duration.seconds(1)
        static let probeTimeout = Duration.seconds(60)
        /// Rest after each recognized image, so that recognition never competes with the user.
        static let recognitionCooldown = Duration.seconds(2)
        /// While the Mac is constrained (`DeviceConditions`), how often recognition looks again.
        static let constrainedRecheckInterval = Duration.seconds(60)
    }

    /// The indexer's name as a consumer of `HistoryTailer`. Keys its position: never change it.
    public static let historyConsumerName = "searchIndexer"

    /// Where the app keeps the queue of images to read: next to the store, in the folder only
    /// the user can read.
    public static let defaultRecognitionQueueURL = PersistentStack.defaultStoreURL
        .deletingLastPathComponent()
        .appending(path: "SearchRecognitionQueue.txt", directoryHint: .notDirectory)

    let index: any SearchIndex
    let dataSource: any SearchIndexerDataSource
    let recognizer: any TextRecognizer
    /// Text recognition waits while the Mac is constrained; indexing does not, so that search
    /// finds everything.
    let conditions: any DeviceConditions
    let sleep: @Sendable (Duration) async throws -> Void
    let log = Log.logger(.search)
    let config: ConfigStore

    private(set) var isRunning = false
    /// Changes with every start and every rebuild: an indexing pass that finds another value
    /// has been superseded and stops.
    private var generation = 0
    /// Changes the index does not have yet, because applying them failed. Tried again with the next ones.
    private var unappliedChanges = SearchIndexChanges()

    /// Image items waiting for their text to be recognized. Saved as it changes
    /// (`recognitionQueueLog`), so that it outlives the app.
    var recognitionQueue = RecognitionQueue()
    let recognitionQueueLog: RecognitionQueueLog
    var recognitionTask: Task<Void, Never>?

    /// - Parameters:
    ///   - recognitionQueueURL: The file the queue of images to read is kept in
    ///     (`defaultRecognitionQueueURL` in the app).
    ///   - conditions: Whether the Mac can spare reading images now.
    ///   - sleep: How the indexer waits (retries, probe timeout, cooldown, constrained Mac).
    public init(
        index: any SearchIndex,
        dataSource: any SearchIndexerDataSource,
        recognizer: any TextRecognizer,
        config: ConfigStore,
        recognitionQueueURL: URL,
        conditions: any DeviceConditions = SystemDeviceConditions(),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.index = index
        self.dataSource = dataSource
        self.recognizer = recognizer
        self.config = config
        recognitionQueueLog = RecognitionQueueLog(url: recognitionQueueURL)
        self.conditions = conditions
        self.sleep = sleep
    }

    /// Registers the indexer with the store's history. Call it before the tailer starts.
    ///
    /// An index that is going to be built from scratch reads the store as it is, so the history
    /// up to now is skipped before the tailer can deliver any of it: on a first launch it would
    /// otherwise hand the indexer the whole history at once, to index a second time alongside
    /// the rebuild.
    public func follow(_ tailer: HistoryTailer) async {
        await tailer.addConsumer(
            named: Self.historyConsumerName,
            onGap: { [weak self] in await self?.rebuild() },
            handler: { [weak self] in await self?.storeDidChange($0) }
        )
        if index.isAvailable, case .rebuild = await startupPlan() {
            await dataSource.skipHistoryToPresent()
        }
    }

    // MARK: - Lifecycle

    /// Brings the index up to date with the store: builds it, continues building it, or checks
    /// that it is still there. Returns when that is done. Does nothing if already started.
    public func start() async {
        guard !isRunning else { return }
        isRunning = true
        generation += 1
        guard index.isAvailable else {
            log.error("Search indexing is not available on this Mac")
            return
        }
        restoreRecognitionQueue()

        switch await startupPlan() {
        case .rebuild(let reason):
            log.info("\(reason.rawValue, privacy: .public), indexing from scratch")
            await rebuild()
        case .resume(let state):
            log.info("Resuming indexing at \(state.indexedItems)/\(state.totalItems) items")
            await indexPendingItems(continuing: state)
        case .probe(let state):
            await checkIndexHealth(expecting: state)
        case .upToDate:
            log.info("Index up to date")
        }
        // Changes delivered before the start were only noted down, and the images the last run
        // did not get to read are waiting: nothing else would take either up before the next
        // change in the store.
        await storeDidChange([])
        recognizeQueuedImagesIfNeeded()
    }

    /// What a start does with the index, by what the last run saved.
    private func startupPlan() async -> SearchIndexerStartup {
        SearchIndexerStartup.plan(
            state: config.value(for: .searchIndexingState).value,
            indexedStoreID: config.value(for: .searchIndexedStoreID).value,
            storeID: await dataSource.storeIdentifier()
        )
    }

    /// Stops indexing and recognizing. What was queued stays queued for the next start.
    public func stop() async {
        isRunning = false
        recognitionTask?.cancel()
        await recognitionTask?.value
    }

    /// Empties the index and indexes every item again: for an index that cannot be trusted
    /// (first launch, another store, another schema, a gap in the history, a lost index).
    public func rebuild() async {
        guard isRunning else {
            // Without saved progress the next start rebuilds.
            config.reset(.searchIndexingState)
            return
        }
        generation += 1
        let generation = generation
        do {
            try await retryingWhileTransient { try await index.deleteAll() }
        } catch {
            log.error("Emptying the index failed: \(error)")
            return
        }
        config.reset(.searchIndexingState)
        // Whatever the history holds up to here is in the store this pass reads.
        await dataSource.skipHistoryToPresent()
        config.set(JSONConfigValue(await dataSource.storeIdentifier()), for: .searchIndexedStoreID)
        guard isCurrent(generation) else { return }
        unappliedChanges = SearchIndexChanges()
        await indexPendingItems(continuing: nil)
    }

    private func isCurrent(_ generation: Int) -> Bool {
        isRunning && generation == self.generation && !Task.isCancelled
    }

    // MARK: - Indexing the whole store

    /// Indexes, batch by batch, every item — or, when continuing, the ones older than the last
    /// one the previous run got to. Progress is saved after each batch.
    private func indexPendingItems(continuing saved: IndexingState?) async {
        let generation = generation
        let ids: [ItemID]
        do {
            ids = try await dataSource.itemIDs(before: saved?.oldestTimestamp)
        } catch {
            log.error("Reading the items to index failed: \(error)")
            return
        }
        guard !ids.isEmpty else { return }

        let total = saved.map { max(ids.count, $0.totalItems) } ?? ids.count
        var state = IndexingState(
            schemaVersion: IndexingState.currentSchemaVersion,
            totalItems: total,
            indexedItems: total - ids.count,
            oldestTimestamp: saved?.oldestTimestamp,
            invalidItems: saved?.invalidItems ?? 0
        )

        for batchStart in stride(from: 0, to: ids.count, by: Metrics.batchLimit) {
            guard isCurrent(generation) else { return }
            let batch = ids[batchStart..<min(batchStart + Metrics.batchLimit, ids.count)]
            let valid = batch.filter { !$0.rawValue.isEmpty }
            do {
                let items = try await dataSource.items(valid)
                try await indexItems(items, isUpdate: false)
                guard isCurrent(generation) else { return }
                state.invalidItems += batch.count - valid.count
                state.indexedItems += batch.count
                state.oldestTimestamp = items.map(\.timestamp).min() ?? state.oldestTimestamp
                config.set(JSONConfigValue(state), for: .searchIndexingState)
                log.info("Indexed \(state.indexedItems)/\(state.totalItems) items")
            } catch {
                // The saved progress makes the next start continue from this batch.
                log.error("Indexing failed at item \(batchStart): \(error)")
                break
            }
        }
        if state.indexedItems >= state.totalItems {
            log.info("Indexing complete (\(state.invalidItems) items without identifier)")
        }
        recognizeQueuedImagesIfNeeded()
    }

    /// Writes the items to the index and queues the images among them for recognition.
    private func indexItems(_ items: [IndexableItem], isUpdate: Bool) async throws {
        guard !items.isEmpty else { return }
        try await retryingWhileTransient {
            try await index.index(items.map { SearchIndexItem($0) }, isUpdate: isUpdate)
        }
        enqueueForRecognition(items)
    }

    // MARK: - Health

    private enum ProbeResult {
        case hasItems
        case isEmpty
        case failed
        case timedOut
    }

    /// The saved state says everything is indexed; the index may have been lost all the same
    /// (the system can discard it). An index that answers "nothing" is rebuilt; one that does
    /// not answer is left alone.
    private func checkIndexHealth(expecting state: IndexingState) async {
        let result = await withTaskGroup(of: ProbeResult.self) { [index, sleep] group in
            group.addTask {
                do {
                    return try await index.containsItems() ? .hasItems : .isEmpty
                } catch {
                    return .failed
                }
            }
            group.addTask {
                try? await sleep(Metrics.probeTimeout)
                return .timedOut
            }
            let first = await group.next() ?? .failed
            group.cancelAll()
            return first
        }
        switch result {
        case .hasItems:
            log.info("Index up to date")
        case .failed:
            log.notice("Index health probe failed, assuming healthy")
        case .timedOut:
            log.notice("Saved state reports \(state.indexedItems) indexed items but the probe never answered")
        case .isEmpty:
            log.error("Saved state reports \(state.indexedItems) indexed items but the index is empty")
            await rebuild()
        }
    }

    // MARK: - Following the store

    /// Applies what happened in the store to the index. Changes that cannot be applied now are
    /// kept and applied with the next ones.
    public func storeDidChange(_ transactions: [HistoryTransaction]) async {
        unappliedChanges.merge(SearchIndexChanges(transactions))
        guard isRunning, !unappliedChanges.isEmpty else { return }
        let changes = unappliedChanges
        unappliedChanges = SearchIndexChanges()
        do {
            if !changes.deleted.isEmpty {
                let deleted = Array(changes.deleted)
                try await retryingWhileTransient { try await index.delete(deleted) }
                dequeueFromRecognition(changes.deleted)
                log.debug("Deleted \(deleted.count) items from the index")
            }
            try await reindexItems(changes.inserted, isUpdate: false)
            try await reindexItems(changes.updated, isUpdate: true)
        } catch {
            log.error("Applying store changes to the index failed: \(error)")
            // What arrived while these were being applied is later than them.
            var pending = changes
            pending.merge(unappliedChanges)
            unappliedChanges = pending
        }
        recognizeQueuedImagesIfNeeded()
    }

    /// Indexes the items again, a batch at a time. The ones the store no longer has come out of
    /// the index instead: whatever the index still says about them is out of date.
    private func reindexItems(_ ids: Set<ItemID>, isUpdate: Bool) async throws {
        let ids = Array(ids)
        for batchStart in stride(from: 0, to: ids.count, by: Metrics.batchLimit) {
            let batch = ids[batchStart..<min(batchStart + Metrics.batchLimit, ids.count)]
            let items = try await dataSource.items(Array(batch))
            let missing = Array(Set(batch).subtracting(items.map(\.id)))
            if !missing.isEmpty {
                try await retryingWhileTransient { try await index.delete(missing) }
                log.info("Removed \(missing.count) items the store no longer has from the index")
            }
            try await indexItems(items, isUpdate: isUpdate)
        }
    }

    // MARK: - Retries

    /// Runs an index write, trying again — after 1 s, then 2 s — while the indexing service
    /// says it is only momentarily unavailable. Any other error is thrown at once.
    func retryingWhileTransient(_ write: () async throws -> Void) async throws {
        var attempt = 1
        while true {
            do {
                return try await write()
            } catch SearchIndexError.transientlyUnavailable(let code) where attempt < Metrics.maxAttempts {
                let delay = Metrics.retryBaseDelay * (1 << (attempt - 1))
                log.notice("Index transiently unavailable (\(code)), retry \(attempt) after \(delay)")
                try await sleep(delay)
                attempt += 1
            }
        }
    }
}
