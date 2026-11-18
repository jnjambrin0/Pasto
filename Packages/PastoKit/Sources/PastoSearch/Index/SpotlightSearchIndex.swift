import CoreSpotlight
import Foundation
import os
import PastoCore
import PastoFoundation
import UniformTypeIdentifiers

/// The search index on Core Spotlight. The index's name only sets it apart for the batch API:
/// what keeps the history out of the system's search is how items are written
/// (`searchableItem(for:isUpdate:)`, `SearchIndexAttribute`).
public actor SpotlightSearchIndex: SearchIndex {
    private static let indexName = "\(Log.subsystem).search"
    private static let domainIdentifier = "\(Log.subsystem).items"

    /// `CSSearchableIndex` is documented as thread-safe but not declared `Sendable`.
    private nonisolated(unsafe) let index: CSSearchableIndex
    private let log = Log.logger(.search)
    /// The latest write, which the next one waits for: the index sees them in the order they were asked.
    private var lastWrite: Task<Void, any Error>?

    public init() {
        self.init(indexName: Self.indexName)
    }

    /// An index under another name: `Tools/CaptureBench` measures one that is not the app's.
    @_spi(Benchmarks)
    public init(indexName: String) {
        index = CSSearchableIndex(name: indexName)
    }

    public nonisolated var isAvailable: Bool {
        CSSearchableIndex.isIndexingAvailable()
    }

    // MARK: - Writing

    /// How long a write may go unanswered before it counts as the service being momentarily
    /// unavailable. Core Spotlight has been seen to leave one call of a long burst without an
    /// answer (Tools/CaptureBench, 2026-11-20); without a limit that write, and every write queued
    /// behind it, would wait forever.
    static let writeTimeout = Duration.seconds(60)
    /// Emptying a large index takes minutes.
    static let deleteAllTimeout = Duration.seconds(15 * 60)
    /// The code of the transient error a write that timed out is reported with.
    static let timeoutCode = -1

    public func index(_ items: [SearchIndexItem], isUpdate: Bool) async throws {
        let withText = items.count { $0.text != nil }
        log.debug("Indexing \(items.count) items (\(withText) with text, \(items.count - withText) without)")
        try await write(timeout: Self.writeTimeout) { index in
            try await index.indexSearchableItems(items.map { Self.searchableItem(for: $0, isUpdate: isUpdate) })
        }
    }

    public func delete(_ ids: [ItemID]) async throws {
        try await write(timeout: Self.writeTimeout) { index in
            try await index.deleteSearchableItems(withIdentifiers: ids.map(\.rawValue))
        }
    }

    public func deleteAll() async throws {
        try await write(timeout: Self.deleteAllTimeout) { index in
            try await index.deleteAllSearchableItems()
        }
    }

    private func write(
        timeout: Duration,
        _ operation: @escaping @Sendable (CSSearchableIndex) async throws -> Void
    ) async throws {
        let previous = lastWrite
        let write = Task { [self, log] in
            // Only its turn matters here: a failed write is reported to whoever asked for it.
            _ = await previous?.result
            do {
                try await Self.unlessUnanswered(after: timeout) { try await operation(self.index) }
            } catch SearchIndexError.transientlyUnavailable(code: Self.timeoutCode) {
                log.error("The index did not answer a write within \(timeout)")
                throw SearchIndexError.transientlyUnavailable(code: Self.timeoutCode)
            } catch {
                throw Self.translated(error)
            }
        }
        lastWrite = write
        try await write.value
    }

    /// Runs `operation`, or gives up on it after `timeout` and throws a transient error. The
    /// operation is left to finish on its own: a Core Spotlight call cannot be called back.
    static func unlessUnanswered(
        after timeout: Duration,
        _ operation: @escaping @Sendable () async throws -> Void
    ) async throws {
        let outcome = OSAllocatedUnfairLock<CheckedContinuation<Void, any Error>?>(initialState: nil)
        try await withCheckedThrowingContinuation { continuation in
            outcome.withLock { $0 = continuation }
            let timer = Task {
                try await Task.sleep(for: timeout)
                outcome.withLock { $0.take() }?.resume(throwing: SearchIndexError.transientlyUnavailable(code: timeoutCode))
            }
            Task {
                do {
                    try await operation()
                    timer.cancel()
                    outcome.withLock { $0.take() }?.resume()
                } catch {
                    timer.cancel()
                    outcome.withLock { $0.take() }?.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Reading

    /// Asks about the last day first and further back only while fewer than `limit` hits have
    /// been found (`SearchWindow`): the same hits a query over all of time gives, without
    /// Spotlight handing over every match of a common word.
    public func newestItemIDs(matching queryString: String, limit: Int) async throws -> [ItemID] {
        log.debug("Query: \(queryString, privacy: .private)")
        var newest = NewestHits(limit: limit)
        var windows = 0
        for window in SearchWindow.sequence(endingAt: Date()) {
            // Each window takes in the one before it: its hits are counted afresh.
            newest = try await SpotlightQueryRun.run(window.restricting(queryString), adding: NewestHits(limit: limit), translate: Self.translated)
            windows += 1
            if newest.isFull { break }
        }
        log.debug("Query returned \(newest.ids.count) hits after \(windows) windows")
        return newest.ids
    }

    public func containsItems() async throws -> Bool {
        let query = CSSearchQuery(queryString: "\(SearchIndexAttribute.type) == \"*\"", queryContext: nil)
        for try await _ in query.results {
            return true
        }
        return false
    }

    // MARK: - Mapping

    /// Pasto's own attributes. `CSCustomAttributeKey` is immutable but not declared `Sendable`.
    private nonisolated(unsafe) static let customKeys = (
        title: customKey(SearchIndexAttribute.title),
        text: customKey(SearchIndexAttribute.text),
        application: customKey(SearchIndexAttribute.application),
        type: customKey(SearchIndexAttribute.type),
        device: customKey(SearchIndexAttribute.device),
        pinboard: customKey(SearchIndexAttribute.pinboard)
    )

    /// Searched only by a query that names the attribute: what makes the history invisible to
    /// the system's search, whose queries name none of Pasto's attributes (`SearchIndexAttribute`).
    private static func customKey(_ name: String) -> CSCustomAttributeKey? {
        CSCustomAttributeKey(keyName: name, searchable: true, searchableByDefault: false, unique: false, multiValued: false)
    }

    /// An item with nothing the system's search could match or show: no title, text, display
    /// name or keywords of Core Spotlight's, only Pasto's own attributes and the date.
    private static func searchableItem(for item: SearchIndexItem, isUpdate: Bool) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .content)
        attributes.contentModificationDate = item.modificationDate
        let custom: [(key: CSCustomAttributeKey?, value: String?)] = [
            (customKeys.title, item.title),
            (customKeys.text, item.text),
            (customKeys.application, item.application),
            (customKeys.type, item.type),
            (customKeys.device, item.device),
            (customKeys.pinboard, item.pinboard),
        ]
        for case (let key?, let value?) in custom {
            attributes.setValue(value as NSString, forCustomKey: key)
        }

        let searchable = CSSearchableItem(
            uniqueIdentifier: item.id.rawValue, domainIdentifier: domainIdentifier, attributeSet: attributes
        )
        // A clipboard item is in the index for as long as it is in the history.
        searchable.expirationDate = .distantFuture
        searchable.isUpdate = isUpdate
        return searchable
    }

    /// The two ways the indexing service says "not right now".
    private static let transientCodes = [
        CSIndexError.Code.indexUnavailableError.rawValue,
        CSIndexError.Code.remoteConnectionError.rawValue,
    ]

    @Sendable
    private static func translated(_ error: any Error) -> any Error {
        let nsError = error as NSError
        if nsError.domain == CSSearchQueryErrorDomain, nsError.code == CSSearchQueryError.Code.cancelled.rawValue {
            return CancellationError()
        }
        guard nsError.domain == CSIndexErrorDomain, transientCodes.contains(nsError.code) else { return error }
        return SearchIndexError.transientlyUnavailable(code: nsError.code)
    }
}
