import Synchronization

/// The result of `operation`, or `expiry` thrown if it has not finished within `limit`.
///
/// The operation and the clock race in tasks of their own and the first to finish decides; the
/// other is cancelled. The caller is let go at once even if the operation ignores cancellation,
/// which a task group could not do. Cancelling the caller cancels both.
func withDeadline<T: Sendable>(
    _ limit: Duration,
    expiry: any Error,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    let race = DeadlineRace<T>()
    return try await withTaskCancellationHandler {
        try await withCheckedThrowingContinuation { continuation in
            race.start(continuation, limit: limit, expiry: expiry, operation: operation)
        }
    } onCancel: {
        race.finish(.failure(CancellationError()))
    }
}

private final class DeadlineRace<T: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<T, any Error>?
        var tasks: [Task<Void, Never>] = []
        /// Set by the first to finish; kept for a `start` that comes after it.
        var outcome: Result<T, any Error>?
    }

    private let state = Mutex(State())

    func start(
        _ continuation: CheckedContinuation<T, any Error>,
        limit: Duration,
        expiry: any Error,
        operation: @escaping @Sendable () async throws -> T
    ) {
        // Cancellation may have come first.
        let earlyOutcome = state.withLock { state in
            if state.outcome == nil { state.continuation = continuation }
            return state.outcome
        }
        if let earlyOutcome {
            continuation.resume(with: earlyOutcome)
            return
        }

        let work = Task {
            do {
                finish(.success(try await operation()))
            } catch {
                finish(.failure(error))
            }
        }
        let clock = Task {
            do {
                try await Task.sleep(for: limit, clock: .continuous)
            } catch {
                return
            }
            finish(.failure(expiry))
        }
        let isOver = state.withLock { state in
            if state.outcome == nil { state.tasks = [work, clock] }
            return state.outcome != nil
        }
        if isOver {
            work.cancel()
            clock.cancel()
        }
    }

    func finish(_ result: Result<T, any Error>) {
        let pending = state.withLock { state -> (CheckedContinuation<T, any Error>?, [Task<Void, Never>])? in
            guard state.outcome == nil else { return nil }
            state.outcome = result
            defer {
                state.continuation = nil
                state.tasks = []
            }
            return (state.continuation, state.tasks)
        }
        guard let (continuation, tasks) = pending else { return }
        tasks.forEach { $0.cancel() }
        continuation?.resume(with: result)
    }
}
