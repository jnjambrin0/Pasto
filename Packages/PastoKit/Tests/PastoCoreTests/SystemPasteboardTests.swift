import Foundation
@_spi(Benchmarks) @testable import PastoCore
import PastoFoundation
import Testing

/// `SystemPasteboard` over an in-memory pasteboard, with its poll and debounce in milliseconds.
/// The rules that move its tokens are tested without timers in `PasteboardChangeTrackerTests`.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SystemPasteboardTests {
    private let ephemeral = EphemeralDefaults()
    private let source = FakePasteboardSource()
    private let pasteboard: SystemPasteboard

    init() {
        pasteboard = SystemPasteboard(
            source: source,
            configuration: SystemPasteboard.Configuration(
                pollInterval: .milliseconds(2),
                pollLeeway: .nanoseconds(0),
                settleDelay: .milliseconds(2),
                maximumCaptureSize: 1 << 30,
                droppedSyncWindow: 1
            ),
            config: ConfigStore(defaults: ephemeral.defaults),
            applications: FakeFrontmostApplication(CaptureFixture.safari)
        )
    }

    /// Starts monitoring and waits for the baseline to be taken.
    private func monitor() -> AsyncStream<SystemPasteboard.Change> {
        let changes = pasteboard.changes()
        pasteboard.queue.sync {}
        return changes
    }

    @Test func aSettledChangeCarriesWhatWasReadAndWhereItCameFrom() async throws {
        var changes = monitor().makeAsyncIterator()

        source.copy([.text("hola")])
        let change = try #require(await changes.next())

        #expect(change.changeCount == source.changeCount)
        #expect(change.coveredChangeCount == 1)
        #expect(change.frontmostApplication?.bundleIdentifier == "com.apple.Safari")
        #expect(change.items == [.text("hola")])
        #expect(!change.isAccessNeeded)
        #expect(pasteboard.changeToken == source.changeCount)
    }

    @Test func askingForChangesAgainEndsTheStreamHandedOutBefore() async throws {
        var first = monitor().makeAsyncIterator()
        var second = monitor().makeAsyncIterator()

        #expect(await first.next() == nil)

        // The pasteboard is still being watched, for the second consumer.
        source.copy([.text("hola")])
        #expect(try #require(await second.next()).items == [.text("hola")])
    }

    @Test func theTokenOfTheLastSessionIsOnlyAStartingPoint() {
        let config = ConfigStore(defaults: ephemeral.defaults)
        config.set(41, for: .pasteboardChangeToken)
        let restored = SystemPasteboard(
            source: source,
            configuration: .standard,
            config: config,
            applications: FakeFrontmostApplication(nil)
        )
        #expect(restored.changeToken == 41)

        // Monitoring takes the live change count as its baseline.
        source.copy([.text("copied before monitoring")])
        restored.startMonitoring()
        restored.queue.sync {}
        #expect(restored.changeToken == source.changeCount)
        restored.stopMonitoring()
    }
}
