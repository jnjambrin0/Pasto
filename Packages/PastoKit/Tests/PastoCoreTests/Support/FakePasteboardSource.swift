import Foundation
import os
@_spi(Benchmarks) @testable import PastoCore

/// An in-memory pasteboard: tests play the applications that copy to it, `SystemPasteboard` reads it.
final class FakePasteboardSource: PasteboardSource, Sendable {
    private struct State {
        var changeCount = 0
        var items: [PasteboardItemSnapshot] = []
        var allowsProgrammaticReads = true
        var isReadable = true
        var requestedTypes: [String] = []
        var readCount = 0
    }

    private let state = OSAllocatedUnfairLock(initialState: State())
    private let reads: AsyncStream<Void>
    private let readSignal: AsyncStream<Void>.Continuation

    init() {
        (reads, readSignal) = AsyncStream.makeStream(of: Void.self)
    }

    // MARK: - What the test does to the pasteboard

    /// An application copies `items`: the contents are replaced and the change count moves.
    func copy(_ items: [PasteboardItemSnapshot]) {
        state.withLock { state in
            state.items = items
            state.changeCount += 1
        }
    }

    /// The owner of the pasteboard adds `items` without the change count moving, as applications
    /// that clear first and write a moment later do.
    func fill(_ items: [PasteboardItemSnapshot]) {
        state.withLock { $0.items = items }
    }

    func setAllowsProgrammaticReads(_ allowed: Bool) {
        state.withLock { $0.allowsProgrammaticReads = allowed }
    }

    func setReadable(_ readable: Bool) {
        state.withLock { $0.isReadable = readable }
    }

    /// Every type whose data has been fetched, in order.
    var requestedTypes: [String] {
        state.withLock { $0.requestedTypes }
    }

    /// How many times the items have been asked for.
    var readCount: Int {
        state.withLock { $0.readCount }
    }

    /// Returns once the items have been asked for more than `count` times.
    func waitForReads(moreThan count: Int) async {
        var iterator = reads.makeAsyncIterator()
        while readCount <= count {
            await iterator.next()
        }
    }

    // MARK: - PasteboardSource

    var changeCount: Int {
        state.withLock { $0.changeCount }
    }

    var allowsProgrammaticReads: Bool {
        state.withLock { $0.allowsProgrammaticReads }
    }

    func items() -> [any PasteboardSourceItem]? {
        defer { readSignal.yield() }
        let snapshots = state.withLock { state in
            state.readCount += 1
            return state.isReadable ? state.items : nil
        }
        return snapshots?.map { Item(snapshot: $0, source: self) }
    }

    func string(forType type: String) -> String? {
        state.withLock { state in
            state.items.lazy.compactMap { $0.dataByType[type] }.first.flatMap { String(data: $0, encoding: .utf8) }
        }
    }

    func write(_ items: [PasteboardItemSnapshot]) -> Int {
        state.withLock { state in
            state.items = items
            state.changeCount += 1
            return state.changeCount
        }
    }

    private struct Item: PasteboardSourceItem {
        let snapshot: PasteboardItemSnapshot
        let source: FakePasteboardSource

        var types: [String] {
            snapshot.types
        }

        func data(forType type: String) -> Data? {
            source.state.withLock { $0.requestedTypes.append(type) }
            return snapshot.dataByType[type]
        }
    }
}
