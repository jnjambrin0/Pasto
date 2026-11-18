@testable import PastoCore
import PastoFoundation

/// What `ItemCollection` and `ListCollection` have in common, so tests can wait on either.
@MainActor
protocol LiveCollection: AnyObject {
    associatedtype ID: Hashable & Sendable
    var onChange: ((CollectionSnapshot<ID>) -> Void)? { get set }
    /// Returns once what earlier writes changed has been published.
    func settle() async
}

extension ItemCollection: LiveCollection {}

extension ListCollection: LiveCollection {
    /// Publishes as it merges: nothing is ever left to publish.
    func settle() async {}
}

extension LiveCollection {
    /// Runs `write` and returns the snapshot the collection publishes because of it, together with
    /// what `write` returned. A write reaches the view context asynchronously; this is how a test
    /// waits for it without sleeping. What earlier writes changed is published first, so that it
    /// is not mistaken for the change `write` makes.
    func change<Result>(by write: () async throws -> Result) async throws -> (snapshot: CollectionSnapshot<ID>, result: Result) {
        await settle()
        let (snapshots, continuation) = AsyncStream.makeStream(of: CollectionSnapshot<ID>.self)
        onChange = { continuation.yield($0) }
        defer { onChange = nil }

        let result = try await write()

        var iterator = snapshots.makeAsyncIterator()
        guard let snapshot = await iterator.next() else {
            throw CancellationError()
        }
        return (snapshot, result)
    }
}
