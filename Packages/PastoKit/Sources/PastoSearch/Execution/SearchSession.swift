import os
import PastoCore
import PastoFoundation

/// The search the panel is showing: takes the query as the user edits it and publishes what
/// to show for it.
@MainActor
public final class SearchSession {
    public enum State: Sendable, Equatable {
        /// The query is empty: the panel shows its lists.
        case idle
        case searching
        /// The matching items, newest first. Never empty.
        case results([ItemID])
        case nothingFound
    }

    /// How long the query has to stay unchanged before it is searched for.
    static let debounce = Duration.milliseconds(120)

    /// How long a search may go unanswered before it shows as finding nothing. A search takes
    /// milliseconds even with a year of history, but Core Spotlight has been seen to leave one
    /// without any answer at all after a long burst of indexing: without a limit the strip would
    /// say "Searching…" until the next key.
    static let timeLimit = Duration.seconds(5)

    public private(set) var state = State.idle {
        didSet {
            if state != oldValue {
                onStateChange?(state)
            }
        }
    }

    /// Called after every change of `state`.
    public var onStateChange: ((State) -> Void)?

    private let service: SearchService
    private let sleep: @Sendable (Duration) async throws -> Void
    private let waitForTimeLimit: @Sendable (Duration) async throws -> Void
    private let log = Log.logger(.search)
    /// The last query that stayed put for the debounce: the one on show, or being searched for.
    private var settledQuery = SearchQuery()
    /// The search for `settledQuery` went unanswered: the next query to settle is searched for
    /// even if it is the same.
    private var settledQueryWentUnanswered = false
    /// Waits out the debounce for the latest query; a newer one starts it again.
    private(set) var debounce: Task<Void, Never>?
    /// The running search; a newly settled query cancels it.
    private(set) var search: Task<Void, Never>?

    /// - Parameters:
    ///   - sleep: How the session waits out the debounce.
    ///   - waitForTimeLimit: How it waits out `timeLimit` while a search runs.
    public init(
        service: SearchService,
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        waitForTimeLimit: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.service = service
        self.sleep = sleep
        self.waitForTimeLimit = waitForTimeLimit
    }

    /// Sets the query. It counts once it has stayed put for the debounce, emptied ones included;
    /// one that settles equal to the last settled one changes nothing, so typing a character
    /// and taking it back within the debounce leaves the search as it was — unless that
    /// search went unanswered, in which case the next key tries again.
    public func update(_ query: SearchQuery) {
        debounce?.cancel()
        debounce = Task { [weak self, sleep] in
            do {
                try await sleep(Self.debounce)
            } catch {
                // Superseded by a newer query, which waits out its own debounce.
                return
            }
            await MainActorReturn.ensure()
            guard !Task.isCancelled else { return }
            self?.settle(on: query)
        }
    }

    private func settle(on query: SearchQuery) {
        guard query != settledQuery || settledQueryWentUnanswered else { return }
        settledQuery = query
        settledQueryWentUnanswered = false
        search?.cancel()
        guard !query.isEmpty else {
            search = nil
            state = .idle
            return
        }
        state = .searching
        search = Task { [weak self] in
            do {
                try await self?.run(query)
            } catch {
                // Cancelled by a newer query, which publishes its own states.
            }
        }
    }

    private func run(_ query: SearchQuery) async throws {
        let results: [ItemID]
        do {
            results = try await resultsWithinTimeLimit(for: query)
        } catch let error as CancellationError {
            throw error
        } catch is Unanswered {
            log.error("Search went unanswered for \(Self.timeLimit, privacy: .public); the next key tries again")
            try Task.checkCancellation()
            settledQueryWentUnanswered = true
            results = []
        } catch {
            // A search that fails shows the same as one that finds nothing.
            log.error("Search failed: \(error)")
            results = []
        }
        try Task.checkCancellation()
        state = results.isEmpty ? .nothingFound : .results(results)
    }

    private struct Unanswered: Error {}

    /// The service's results, or `Unanswered` once `timeLimit` has gone by without them; the
    /// search left behind is cancelled.
    private func resultsWithinTimeLimit(for query: SearchQuery) async throws -> [ItemID] {
        let search = Task { [service] in try await service.results(for: query) }
        let expired = OSAllocatedUnfairLock(initialState: false)
        let timeLimit = Task { [waitForTimeLimit] in
            try await waitForTimeLimit(Self.timeLimit)
            expired.withLock { $0 = true }
            search.cancel()
        }
        defer { timeLimit.cancel() }
        return try await withTaskCancellationHandler {
            do {
                return try await search.value
            } catch {
                throw expired.withLock { $0 } ? Unanswered() : error
            }
        } onCancel: {
            search.cancel()
        }
    }
}
