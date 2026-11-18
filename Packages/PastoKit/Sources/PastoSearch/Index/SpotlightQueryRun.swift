import CoreSpotlight
import Foundation
import os
import PastoCore

/// One `CSSearchQuery`, from start to completion, keeping the newest of its hits.
///
/// The query's own handlers are used rather than its asynchronous sequence: hits arrive in
/// batches, which costs one lock per batch instead of a suspension per hit, and cancelling the
/// task that awaits the run cancels the query at once — a keystroke replaces the search it
/// makes obsolete without waiting for Spotlight to finish it.
final class SpotlightQueryRun: Sendable {
    private enum Progress {
        case notStarted
        case running(CheckedContinuation<Void, any Error>)
        case over
    }

    private struct State {
        var hits: NewestHits
        var progress = Progress.notStarted
        var isCancelled = false
    }

    private let state: OSAllocatedUnfairLock<State>

    private init(hits: NewestHits) {
        state = OSAllocatedUnfairLock(uncheckedState: State(hits: hits))
    }

    /// Runs `queryString` and returns `hits` with the query's hits added.
    ///
    /// - Throws: `CancellationError` when the awaiting task is cancelled; otherwise what the query
    ///   failed with, after `translate`.
    static func run(
        _ queryString: String,
        adding hits: NewestHits,
        translate: @escaping @Sendable (any Error) -> any Error
    ) async throws -> NewestHits {
        let context = CSSearchQueryContext()
        // The date is all a hit is ranked by.
        context.fetchAttributes = [SearchIndexAttribute.modificationDate]
        // Started, cancelled and handed its handlers from different threads, which the query allows.
        nonisolated(unsafe) let query = CSSearchQuery(queryString: queryString, queryContext: context)
        let run = SpotlightQueryRun(hits: hits)
        query.foundItemsHandler = { items in
            run.add(items.map { (ItemID(rawValue: $0.uniqueIdentifier), $0.attributeSet.contentModificationDate) })
        }
        query.completionHandler = { error in
            run.finish(error.map(translate))
        }
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                if run.begin(continuation) {
                    query.start()
                }
            }
        } onCancel: {
            run.cancel()
            query.cancel()
        }
        return run.state.withLockUnchecked { $0.hits }
    }

    private func add(_ items: [(id: ItemID, date: Date?)]) {
        state.withLockUnchecked { state in
            for item in items {
                state.hits.insert(item.id, date: item.date)
            }
        }
    }

    /// Whether the query should start: not when the task was cancelled before it could.
    private func begin(_ continuation: CheckedContinuation<Void, any Error>) -> Bool {
        let wasCancelled = state.withLockUnchecked { state -> Bool in
            guard !state.isCancelled else {
                state.progress = .over
                return true
            }
            state.progress = .running(continuation)
            return false
        }
        if wasCancelled {
            continuation.resume(throwing: CancellationError())
        }
        return !wasCancelled
    }

    private func finish(_ error: (any Error)?) {
        guard let continuation = takeContinuation() else { return }
        if let error {
            continuation.resume(throwing: error)
        } else {
            continuation.resume()
        }
    }

    private func cancel() {
        let continuation = state.withLockUnchecked { state -> CheckedContinuation<Void, any Error>? in
            state.isCancelled = true
            guard case .running(let continuation) = state.progress else { return nil }
            state.progress = .over
            return continuation
        }
        continuation?.resume(throwing: CancellationError())
    }

    /// The continuation, the first time it is asked for; resuming it is then the caller's.
    private func takeContinuation() -> CheckedContinuation<Void, any Error>? {
        state.withLockUnchecked { state in
            guard case .running(let continuation) = state.progress else { return nil }
            state.progress = .over
            return continuation
        }
    }
}
