import PastoCore

/// Runs searches: asks the index and settles the answer against the store.
@MainActor
public final class SearchService {
    /// How many items a search returns at most: the newest ones that match.
    public static let resultLimit = 100

    private let index: any SearchIndex
    private let reader: StoreReader

    public init(index: any SearchIndex, reader: StoreReader) {
        self.index = index
        self.reader = reader
    }

    /// The items that match `query`, newest first. Empty for a query that asks for nothing.
    ///
    /// Cancelling the task that awaits it abandons the search with `CancellationError`.
    public func results(for query: SearchQuery) async throws -> [ItemID] {
        guard let queryString = SearchQueryString.make(for: query) else { return [] }
        let hits = try await index.newestItemIDs(matching: queryString, limit: Self.resultLimit)
        try Task.checkCancellation()
        // The store has the last word: on which items still exist, and on their order.
        return reader.itemIDs(among: hits)
    }
}
