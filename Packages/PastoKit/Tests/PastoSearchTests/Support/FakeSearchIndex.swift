import PastoCore
@testable import PastoSearch

/// An index in memory that records what it is asked to do and fails on demand.
actor FakeSearchIndex: SearchIndex {
    enum Operation: Equatable {
        case index(count: Int, isUpdate: Bool)
        case delete([ItemID])
        case deleteAll
    }

    nonisolated let isAvailable: Bool

    private(set) var items: [ItemID: SearchIndexItem] = [:]
    private(set) var operations: [Operation] = []
    private(set) var queryStrings: [String] = []
    /// Thrown, first in first out, by writes instead of doing them, once `writesBeforeFailing` have gone through.
    private var writeFailures: [any Error] = []
    private var writesBeforeFailing = 0
    /// What every query matches, in the order the index would return it.
    private var hits: [ItemID] = []

    private let operationFeed = AsyncStream.makeStream(of: Operation.self)

    init(isAvailable: Bool = true) {
        self.isAvailable = isAvailable
    }

    /// Every write, as it happens: lets a test wait for one without sleeping.
    nonisolated var operationStream: AsyncStream<Operation> {
        operationFeed.stream
    }

    func failWrites(after successfulWrites: Int = 0, with errors: [any Error]) {
        writesBeforeFailing = successfulWrites
        writeFailures = errors
    }

    func setHits(_ ids: [ItemID]) {
        hits = ids
    }

    /// Queries never answer until cancelled, as Core Spotlight's queries can after a long burst
    /// of writes.
    private var isUnresponsive = false

    func setUnresponsive(_ value: Bool) {
        isUnresponsive = value
    }

    /// Loses everything, as the system may do to a real index.
    func lose() {
        items = [:]
        operations = []
    }

    func forgetOperations() {
        operations = []
    }

    // MARK: - SearchIndex

    func index(_ items: [SearchIndexItem], isUpdate: Bool) async throws {
        try failIfAsked()
        for item in items {
            self.items[item.id] = item
        }
        record(.index(count: items.count, isUpdate: isUpdate))
    }

    func delete(_ ids: [ItemID]) async throws {
        try failIfAsked()
        ids.forEach { items[$0] = nil }
        record(.delete(ids))
    }

    func deleteAll() async throws {
        try failIfAsked()
        items = [:]
        record(.deleteAll)
    }

    func newestItemIDs(matching queryString: String, limit: Int) async throws -> [ItemID] {
        queryStrings.append(queryString)
        if isUnresponsive {
            // Ends only by cancellation.
            try await Task.sleep(for: .seconds(3_600))
        }
        return Array(hits.prefix(limit))
    }

    func containsItems() async throws -> Bool {
        !items.isEmpty
    }

    private func failIfAsked() throws {
        guard writesBeforeFailing == 0 else {
            writesBeforeFailing -= 1
            return
        }
        if !writeFailures.isEmpty {
            throw writeFailures.removeFirst()
        }
    }

    private func record(_ operation: Operation) {
        operations.append(operation)
        operationFeed.continuation.yield(operation)
    }
}
