import Foundation
import PastoCore

/// What the indexer reads from the store.
public protocol SearchIndexerDataSource: Sendable {
    /// Identifies the store: an index built from another one is of no use.
    func storeIdentifier() async -> String?
    /// The identifiers of every item, newest first; with a date, only of those last used before it.
    func itemIDs(before date: Date?) async throws -> [ItemID]
    /// The existing items among `ids`.
    func items(_ ids: [ItemID]) async throws -> [IndexableItem]
    /// The encoded image of an image item, to recognize its text.
    func imageData(for id: ItemID) async throws -> Data?
    /// Called before indexing the whole store: the changes saved until now are covered by that
    /// and need not be delivered to the indexer.
    func skipHistoryToPresent() async
}

/// The indexer's view of the user's store.
public struct StoreIndexerDataSource: SearchIndexerDataSource {
    private let reader: IndexableItemReader
    private let tailer: HistoryTailer

    /// - Parameter tailer: The one the indexer follows (`SearchIndexer.follow`).
    public init(reader: IndexableItemReader, tailer: HistoryTailer) {
        self.reader = reader
        self.tailer = tailer
    }

    public func storeIdentifier() async -> String? {
        reader.storeIdentifier
    }

    public func itemIDs(before date: Date?) async throws -> [ItemID] {
        try await reader.itemIDs(before: date)
    }

    public func items(_ ids: [ItemID]) async throws -> [IndexableItem] {
        try await reader.items(ids)
    }

    public func imageData(for id: ItemID) async throws -> Data? {
        try await reader.imageData(for: id)
    }

    public func skipHistoryToPresent() async {
        await tailer.skipToPresent(consumerNamed: SearchIndexer.historyConsumerName)
    }
}
