@testable import PastoPicks
import Testing

/// The deadline and the one-at-a-time turn the language model requests go through.
struct ConcurrencyTests {
    private struct Expired: Error, Equatable {}

    @Test func anOperationThatFinishesInTimeGivesItsResult() async throws {
        let value = try await withDeadline(.seconds(10), expiry: Expired()) { 42 }
        #expect(value == 42)
    }

    @Test func aSlowOperationThrowsTheExpiryAtTheDeadline() async {
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: Expired.self) {
            try await withDeadline(.milliseconds(20), expiry: Expired()) {
                // Ignores cancellation on purpose: the caller must not wait for it.
                try? await Task.sleep(for: .seconds(30))
                return 0
            }
        }
        #expect(start.duration(to: clock.now) < .seconds(10))
    }

    @Test func theOperationsErrorIsPassedOn() async {
        await #expect(throws: Expired.self) {
            try await withDeadline(.seconds(10), expiry: CancellationError()) { () async throws -> Int in throw Expired() }
        }
    }

    @Test func cancellingTheCallerCancelsTheWait() async {
        let task = Task {
            try await withDeadline(.seconds(30), expiry: Expired()) {
                try? await Task.sleep(for: .seconds(30))
                return 0
            }
        }
        task.cancel()
        await #expect(throws: CancellationError.self) { try await task.value }
    }

    @Test func theTurnGoesInOrderAndSkipsWhoLeftTheLine() async throws {
        let turn = GenerationTurn()
        try await turn.take()

        let leaving = Task { try await turn.take() }
        let staying = Task { try await turn.take() }
        // Give both time to queue up, in this order.
        try await Task.sleep(for: .milliseconds(50))
        leaving.cancel()
        await #expect(throws: CancellationError.self) { try await leaving.value }

        await turn.release()
        try await staying.value
        await turn.release()
        // Free again: taking it does not wait.
        try await turn.take()
    }
}
