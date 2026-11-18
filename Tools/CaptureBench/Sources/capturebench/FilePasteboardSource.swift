import Foundation
import os
@_spi(Benchmarks) import PastoCore

/// A pasteboard of the benchmark's own. Copying puts representations on it by reference to
/// files; reading one loads the file into fresh memory, as data from the pasteboard server does.
/// It never touches the general pasteboard.
final class FilePasteboardSource: PasteboardSource, Sendable {
    enum Content: Sendable {
        case file(URL)
        case bytes(Data)
    }

    struct Representation: Sendable {
        let type: String
        let content: Content
    }

    private struct State {
        var changeCount = 1
        var items: [[Representation]] = []
        /// When the representations of the latest copy were first and last fetched.
        var firstFetch: ContinuousClock.Instant?
        var lastFetch: ContinuousClock.Instant?
        var onFetchesDone: (@Sendable () -> Void)?
        var pendingFetches = 0
        /// First and last fetch of every copy whose representations have all been read, in order.
        var completedFetches: [(first: ContinuousClock.Instant, last: ContinuousClock.Instant)] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    /// An application copies `items`. `onFetched` runs once every representation of them has
    /// been read.
    func copy(_ items: [[Representation]], onFetched: (@Sendable () -> Void)? = nil) {
        state.withLock { state in
            state.items = items
            state.changeCount += 1
            state.firstFetch = nil
            state.lastFetch = nil
            state.pendingFetches = items.reduce(0) { $0 + $1.count }
            state.onFetchesDone = onFetched
        }
    }

    /// When the representations of the first copy were first and last fetched.
    var fetchInterval: (first: ContinuousClock.Instant, last: ContinuousClock.Instant)? {
        state.withLock { $0.completedFetches.first }
    }

    // MARK: - PasteboardSource

    var changeCount: Int {
        state.withLock { $0.changeCount }
    }

    var allowsProgrammaticReads: Bool { true }

    func items() -> [any PasteboardSourceItem]? {
        state.withLock { $0.items }.map { Item(representations: $0, source: self) }
    }

    func string(forType type: String) -> String? {
        nil
    }

    func write(_ items: [PasteboardItemSnapshot]) -> Int {
        state.withLock { state in
            state.changeCount += 1
            return state.changeCount
        }
    }

    fileprivate func read(_ content: Content) -> Data? {
        let start = ContinuousClock.now
        let data: Data? = switch content {
        case .bytes(let bytes): bytes
        case .file(let url): try? FileHandle(forReadingFrom: url).readToEnd()
        }
        let done = state.withLock { state -> (@Sendable () -> Void)? in
            state.firstFetch = state.firstFetch ?? start
            state.lastFetch = .now
            state.pendingFetches -= 1
            guard state.pendingFetches == 0, let first = state.firstFetch, let last = state.lastFetch else { return nil }
            state.completedFetches.append((first, last))
            return state.onFetchesDone
        }
        done?()
        return data
    }

    private struct Item: PasteboardSourceItem {
        let representations: [Representation]
        let source: FilePasteboardSource

        var types: [String] {
            representations.map(\.type)
        }

        func data(forType type: String) -> Data? {
            guard let representation = representations.first(where: { $0.type == type }) else { return nil }
            return source.read(representation.content)
        }
    }
}

extension Payload {
    var pasteboardItem: [FilePasteboardSource.Representation] {
        representations.map { .init(type: $0.type, content: .file($0.file)) }
    }
}
