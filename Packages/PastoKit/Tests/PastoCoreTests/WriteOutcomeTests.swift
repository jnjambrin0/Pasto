import Foundation
import PastoCore
import Testing

/// What the writer tells about its writes, which the card about failed saves follows.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WriteOutcomeTests {
    private struct DiskFull: Error {}

    @Test func savesAndFailuresAreToldAndRejectionsAreNot() async throws {
        let store = try StoreFixture()
        var outcomes = store.writer.outcomes().makeAsyncIterator()

        _ = try await store.record(["a"])
        #expect(await outcomes.next() == .saved)

        // Rejected for what it asked: nothing to say about the store.
        await #expect(throws: StoreError.self) {
            try await store.writer.perform(author: .user) { _ in throw StoreError.invalidOperation("test") }
        }
        // Nor about a transaction that changed nothing.
        try await store.writer.perform(author: .user) { _ in }
        _ = try await store.record(["b"])
        #expect(await outcomes.next() == .saved)

        await #expect(throws: DiskFull.self) {
            try await store.writer.perform(author: .capture) { _ in throw DiskFull() }
        }
        #expect(await outcomes.next() == .failed)
    }
}
