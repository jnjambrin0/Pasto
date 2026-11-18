import Foundation
import PastoCore
import Testing

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct StoreChangesTests {
    @Test func aWriteIsAnnouncedOnceTheReaderCanSeeIt() async throws {
        let store = try StoreFixture()
        var changes = store.reader.changes().makeAsyncIterator()

        let ids = try await store.record(["a"])

        // Never arrives if writes are not announced; the suite's time limit then fails the test.
        await changes.next()
        #expect(store.reader.item(ids[0]) != nil)
    }
}
