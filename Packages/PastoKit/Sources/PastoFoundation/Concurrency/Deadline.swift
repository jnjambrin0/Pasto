import Foundation
import Synchronization

/// Waits for something for a limited time: the launch never waits without end on a system
/// service that does not answer.
///
/// Unlike a task group, which waits for all its tasks before it returns, this returns when the
/// time is up even if the operation ignores cancellation; the operation is cancelled and left
/// to finish on its own.
public nonisolated enum Deadline {
    /// The operation's result, or nil when `limit` passed first. An error the operation throws
    /// in time is thrown.
    public static func run<T: Sendable>(
        within limit: Duration,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        let outcome: Result<T, any Error>? = await withCheckedContinuation { continuation in
            let gate = Gate<Result<T, any Error>?>(continuation)
            let work = Task {
                do {
                    gate.open(with: .success(try await operation()))
                } catch {
                    gate.open(with: .failure(error))
                }
            }
            let timer = Task {
                try? await Task.sleep(for: limit)
                guard !Task.isCancelled else { return }
                gate.open(with: nil)
                work.cancel()
            }
            gate.whenOpen { timer.cancel() }
        }
        return try outcome?.get()
    }

    /// Runs an operation that cannot fail and returns nothing, giving up after `limit`: true when
    /// it finished in time.
    @discardableResult
    public static func finishes(within limit: Duration, _ operation: @escaping @Sendable () async -> Void) async -> Bool {
        let finished: Bool? = try? await run(within: limit) { () async throws -> Bool in
            await operation()
            return true
        }
        return finished == true
    }
}

/// Resumes a continuation once, with whichever value comes first.
private nonisolated final class Gate<Value: Sendable>: Sendable {
    private struct State {
        var continuation: CheckedContinuation<Value, Never>?
        var onOpen: (@Sendable () -> Void)?
        var isOpen = false
    }

    private let state: Mutex<State>

    init(_ continuation: CheckedContinuation<Value, Never>) {
        state = Mutex(State(continuation: continuation))
    }

    /// Runs `action` once the gate opens; at once if it already has.
    func whenOpen(_ action: @escaping @Sendable () -> Void) {
        let runsNow = state.withLock { state -> Bool in
            guard !state.isOpen else { return true }
            state.onOpen = action
            return false
        }
        if runsNow { action() }
    }

    func open(with value: Value) {
        let opened = state.withLock { state -> (CheckedContinuation<Value, Never>, (@Sendable () -> Void)?)? in
            guard !state.isOpen, let continuation = state.continuation else { return nil }
            state.isOpen = true
            state.continuation = nil
            defer { state.onOpen = nil }
            return (continuation, state.onOpen)
        }
        guard let (continuation, onOpen) = opened else { return }
        onOpen?()
        continuation.resume(returning: value)
    }
}
