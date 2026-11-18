import CoreData
import Foundation
import os
@_spi(Benchmarks) @testable import PastoCore
import PastoFoundation

/// The whole capture pipeline over an in-memory pasteboard and an in-memory store: the test
/// copies, `SystemPasteboard` notices and reads, `HistoryManager` records.
@MainActor
final class CaptureFixture {
    /// Poll and debounce in a few milliseconds; everything else as in the app.
    private static let configuration = SystemPasteboard.Configuration(
        pollInterval: .milliseconds(2),
        pollLeeway: .nanoseconds(0),
        settleDelay: .milliseconds(2),
        maximumCaptureSize: SystemPasteboard.Configuration.standard.maximumCaptureSize,
        droppedSyncWindow: SystemPasteboard.Configuration.standard.droppedSyncWindow
    )

    static let safari = FrontmostApplication(
        bundleIdentifier: "com.apple.Safari",
        name: "Safari",
        icon: TestImage.solid(.red, width: 256, height: 256)
    )

    let store: StoreFixture
    let config: ConfigStore
    let source = FakePasteboardSource()
    let applications = FakeFrontmostApplication(CaptureFixture.safari)
    let clock = TestClock()
    let pasteboard: SystemPasteboard
    let manager: HistoryManager

    private let ephemeral = EphemeralDefaults()
    private let events: AsyncStream<CaptureEvent>

    /// - Parameter starts: Whether capture is started right away.
    init(starts: Bool = true, linkMetadataProvider: (any LinkMetadataProviding)? = nil) async throws {
        store = try StoreFixture()
        config = ConfigStore(defaults: ephemeral.defaults)
        pasteboard = SystemPasteboard(
            source: source,
            configuration: Self.configuration,
            config: config,
            applications: applications
        )
        manager = HistoryManager(pasteboard: pasteboard, writer: store.writer, config: config, linkMetadataProvider: linkMetadataProvider, now: clock.now)
        events = await manager.events()
        if starts {
            await start()
        }
    }

    func start() async {
        await manager.start()
        waitForPasteboardQueue()
    }

    /// Returns once everything already queued on the pasteboard's queue has run: the baseline
    /// taken when monitoring starts, or a read that is under way.
    func waitForPasteboardQueue() {
        pasteboard.queue.sync {}
    }

    /// An application copies `items`; returns what the manager reports about it.
    func copy(_ items: [PasteboardItemSnapshot]) async -> CaptureEvent? {
        source.copy(items)
        return await nextEvent()
    }

    func copy(_ text: String) async -> CaptureEvent? {
        await copy([.text(text)])
    }

    /// An application copies `items`, which are expected not to become an item; returns once the
    /// read that looked at them is over.
    func copyWithoutCapture(_ items: [PasteboardItemSnapshot]) async {
        let readsBefore = source.readCount
        source.copy(items)
        await source.waitForReads(moreThan: readsBefore)
        waitForPasteboardQueue()
    }

    func nextEvent() async -> CaptureEvent? {
        var iterator = events.makeAsyncIterator()
        return await iterator.next()
    }

    /// The history as the store has it right now, newest first. Read on the writer's context:
    /// the view context only catches up some time after a write.
    func history() async throws -> [Item] {
        try await store.writer.perform(author: .maintenance) { context in
            let request = ItemEntity.makeRequest(ItemListQuery.predicate(for: .clipboard))
            request.sortDescriptors = ItemListQuery.sortDescriptors(for: .clipboard)
            return try context.context.fetch(request).map(Item.init)
        }
    }

    func setCapacity(_ capacity: HistoryCapacity) async throws {
        try await store.writer.perform(author: .user) { context in
            try context.list(.clipboard).setAttributes(.clipboard(capacity: capacity))
        }
    }
}

/// The frontmost application is whatever the test says.
@MainActor
final class FakeFrontmostApplication: FrontmostApplicationProviding {
    var application: FrontmostApplication?

    init(_ application: FrontmostApplication?) {
        self.application = application
    }

    func frontmostApplication() -> FrontmostApplication? {
        application
    }
}

/// A clock the test moves by hand.
final class TestClock: Sendable {
    private let date = OSAllocatedUnfairLock(initialState: Date(timeIntervalSinceReferenceDate: 800_000_000))

    var now: @Sendable () -> Date {
        { [date] in date.withLock { $0 } }
    }

    func advance(days: Double) {
        date.withLock { $0.addTimeInterval(days * 24 * 60 * 60) }
    }
}
