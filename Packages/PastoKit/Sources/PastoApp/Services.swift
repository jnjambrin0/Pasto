import Foundation
import os
import PastoCore
import PastoFoundation
import PastoPicks
import PastoRecognition
import PastoSearch
import PastoUpdates

/// The long-lived services of the app, created once at launch and handed to whoever needs them.
struct Services {
    let config: ConfigStore
    let reader: StoreReader
    let writer: StoreWriter
    /// Writes what the user does to items, and owns the undo manager those changes go on.
    let itemWriter: UndoableWriter
    let pasteboard: SystemPasteboard
    let historyManager: HistoryManager
    let restorer: ItemRestorer
    let searchIndex: any SearchIndex
    /// Suggestions: what to paste where the panel opened.
    let picks: PicksProvider
    /// Software updates; never started on Debug builds or with a store in memory.
    let updates: UpdateController
    private let historyTailer: HistoryTailer
    private let searchIndexer: SearchIndexer

    /// - Parameter inMemory: Keep the history in memory only, leaving the user's store alone
    ///   (development and measurement runs).
    init(inMemory: Bool) throws {
        let config = ConfigStore()
        if !inMemory {
            // The store holds everything the user copied: only they may read it.
            _ = try? OwnerOnlyAccess.restrict(PersistentStack.defaultStoreURL.deletingLastPathComponent())
        }
        let stack = try PersistentStack(location: inMemory ? .inMemory : .onDisk(PersistentStack.defaultStoreURL))
        let reader = StoreReader(stack: stack)
        let writer = StoreWriter(stack: stack)
        let pasteboard = SystemPasteboard(config: config)

        self.config = config
        self.reader = reader
        self.writer = writer
        itemWriter = UndoableWriter(writer: writer)
        self.pasteboard = pasteboard
        historyManager = HistoryManager(
            pasteboard: pasteboard,
            writer: writer,
            config: config,
            linkMetadataProvider: SystemLinkMetadataProvider()
        )
        restorer = ItemRestorer(reader: reader, writer: writer, pasteboard: pasteboard, config: config)

        // What suggestions learn stays out of the user's folder on runs with a store in memory.
        picks = PicksProvider(
            config: config,
            reader: RecentItemReader(stack: stack),
            directory: inMemory
                ? URL.temporaryDirectory.appending(path: "PastoPicks-\(UUID().uuidString)", directoryHint: .isDirectory)
                : PicksProvider.defaultDirectory
        )
        updates = UpdateController(isDebugBuild: Self.isDebugBuild, isDevelopmentRun: inMemory)

        let searchIndex = SpotlightSearchIndex()
        let historyTailer = HistoryTailer(stack: stack, config: config)
        self.searchIndex = searchIndex
        self.historyTailer = historyTailer
        searchIndexer = SearchIndexer(
            index: searchIndex,
            dataSource: StoreIndexerDataSource(reader: IndexableItemReader(stack: stack), tailer: historyTailer),
            recognizer: VisionTextRecognizer(),
            config: config,
            // Like suggestions, out of the user's folder on runs with a store in memory.
            recognitionQueueURL: inMemory
                ? URL.temporaryDirectory.appending(path: "PastoRecognitionQueue-\(UUID().uuidString).txt")
                : SearchIndexer.defaultRecognitionQueueURL
        )
    }

    private static var isDebugBuild: Bool {
        #if DEBUG
        true
        #else
        false
        #endif
    }

    /// Starts keeping the search index in step with the store: what is not indexed yet first,
    /// then every change as it is saved. Store maintenance follows (`startMaintenance`).
    func startIndexing() async {
        await searchIndexer.follow(historyTailer)
        Task(priority: .utility) { [searchIndexer] in await searchIndexer.start() }
        // Image copies left in the temporary folder by earlier pastes.
        Task.detached(priority: .utility) { ItemRestorer.removeTemporaryImageCopies() }
        await historyTailer.start()
        startMaintenance()
    }

    /// Keeps the store from growing without bound: once the history's consumers have caught up
    /// after launch, and then every day, the persistent history older than a week goes — never
    /// what a consumer has not been given — and the space the store no longer uses goes back to
    /// the disk. Off the main actor, and on the writer's queue for the latter, so never during a
    /// capture.
    private func startMaintenance() {
        Task.detached(priority: .utility) { [historyTailer, writer] in
            let log = Log.logger(.store)
            await historyTailer.waitUntilCaughtUp()
            while !Task.isCancelled {
                do {
                    try await historyTailer.purge(before: Date().addingTimeInterval(-StoreMaintenancePolicy.historyWindow))
                    try await writer.performMaintenance()
                } catch {
                    log.error("Store maintenance failed: \(error)")
                }
                try? await Task.sleep(for: StoreMaintenancePolicy.interval)
            }
        }
    }
}
