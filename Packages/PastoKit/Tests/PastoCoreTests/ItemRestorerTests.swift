import Foundation
@testable import PastoCore
import PastoFoundation
import Testing

/// Putting items of the history back on the pasteboard, end to end against an in-memory store. The
/// pasteboard is a double: nothing here touches the real one.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct ItemRestorerTests {
    private let store: StoreFixture
    private let pasteboard = RecordingPasteboard()
    private let ephemeral = EphemeralDefaults()
    private let folder = TemporaryFolder()

    init() throws {
        store = try StoreFixture()
    }

    private var config: ConfigStore { ConfigStore(defaults: ephemeral.defaults) }

    /// - Parameter second: What the restorer's clock reads first; every reading adds a second.
    private func makeRestorer(clockStartingAt second: TimeInterval = 1_000, environment: [String: String] = [:]) -> ItemRestorer {
        let clock = TickingClock(startingAt: .second(second))
        return ItemRestorer(
            reader: store.reader,
            writer: store.writer,
            pasteboard: pasteboard,
            config: config,
            now: { clock.now() },
            temporaryDirectory: folder.url,
            environment: environment
        )
    }

    private func record(_ item: NewItem) async throws -> ItemID {
        try await store.writer.perform(author: .capture) { try $0.record(item).id }
    }

    private var history: [ItemID] {
        store.reader.itemCollection(for: .clipboard).snapshot.ids
    }

    // MARK: - Nothing to restore

    @Test func returnsFalseAndTouchesNothingWhenThereIsNothingToRestore() {
        let restorer = makeRestorer()

        #expect(!restorer.restore([], options: []))
        #expect(!restorer.restore([ItemID(rawValue: "gone")], options: []))

        #expect(pasteboard.writes.isEmpty)
        #expect(!config.isSet(.pasteboardChangeToken))
        #expect(restorer.historyUpdate == nil)
    }

    // MARK: - Writing

    @Test func writesTheComposedItemsAndRemembersTheChangeCount() async throws {
        let id = try await record(.text("hello", at: 1, from: .safari))
        let restorer = makeRestorer()

        #expect(restorer.restore([id], options: []))

        #expect(pasteboard.writes == [[PasteboardItemSnapshot.plainText("hello").signed(from: "com.apple.Safari")]])
        #expect(config.value(for: .pasteboardChangeToken) == pasteboard.changeCount)
    }

    @Test func itemsThatNoLongerExistAreLeftOut() async throws {
        let ids = try await store.record(["a", "b"])
        let restorer = makeRestorer()
        let events = restorer.events()

        #expect(restorer.restore([ids[1], ItemID(rawValue: "gone"), ids[0]], options: .textAsPlainText))

        // Two texts, so one merged element, in the order asked for.
        #expect(pasteboard.writes == [[
            PasteboardItemSnapshot(["public.utf8-plain-text": Data("b\na".utf8), "jnjambrino.Pasto": Data()]),
        ]])
        var iterator = events.makeAsyncIterator()
        let event = await iterator.next()
        #expect(event == RestoreEvent(itemIDs: [ids[1], ids[0]]))
    }

    @Test func theOptionsDecideTheFormOfWhatIsWritten() async throws {
        let rich = PasteboardItemSnapshot(["public.html": Data("<b>hello</b>".utf8), "public.utf8-plain-text": Data("hello".utf8)])
        let id = try await record(NewItem(
            type: .text, checksum: "rich", preview: .unknown, pasteboardItems: [rich], timestamp: .second(1)
        ))
        let restorer = makeRestorer()

        #expect(restorer.restore([id], options: []))
        #expect(restorer.restore([id], options: .textAsPlainText))

        #expect(pasteboard.writes == [[rich.signed()], [PasteboardItemSnapshot.plainText("hello").signed()]])
    }

    @Test func anImageIsWrittenWithATemporaryCopyUnlessSandboxed() async throws {
        let png = PasteboardItemSnapshot(["public.png": Data("png".utf8)])
        let id = try await record(NewItem(
            type: .image, checksum: "image", preview: .unknown, pasteboardItems: [png], sourceApplication: .safari, timestamp: .second(1)
        ))

        #expect(makeRestorer(environment: ["APP_SANDBOX_CONTAINER_ID": "jnjambrino.Pasto"]).restore([id], options: []))
        #expect(pasteboard.writes.last == [png.signed(from: "com.apple.Safari")])
        #expect(folder.imageFilenames.isEmpty)

        #expect(makeRestorer().restore([id], options: []))
        let written = try #require(pasteboard.writes.last?.first)
        #expect(written.types == ["public.png", "public.file-url", "org.nspasteboard.source", "jnjambrino.Pasto"])
        // Its exact name depends on the time zone; the processor's tests pin it down.
        let copy = try #require(folder.imageFilenames.first)
        #expect(copy.hasPrefix("Safari ") && copy.hasSuffix(".png"))
        #expect(written.dataByType["public.file-url"] == Data(folder.images.appending(path: copy).absoluteString.utf8))
    }

    // MARK: - Event

    @Test func publishesTheRestoreBeforeReturning() async throws {
        let ids = try await store.record(["a", "b"])
        let restorer = makeRestorer()
        let events = restorer.events()

        #expect(restorer.restore([ids[0]], options: []))
        #expect(restorer.restore([ids[1]], options: .plainText))

        // Both are already in the stream: nothing was awaited between the restores and here.
        var iterator = events.makeAsyncIterator()
        let first = await iterator.next()
        let second = await iterator.next()
        #expect(first == RestoreEvent(itemIDs: [ids[0]]))
        #expect(second == RestoreEvent(itemIDs: [ids[1]]))
    }

    @Test func tellsItsObserverInsideTheRestoreOnceThePasteboardIsWritten() async throws {
        let ids = try await store.record(["a", "b"])
        let restorer = makeRestorer()
        var observed: [(event: RestoreEvent, writes: Int)] = []
        restorer.onRestore = { [pasteboard] in observed.append(($0, pasteboard.writes.count)) }

        #expect(restorer.restore([ids[0]], options: []))
        // No turn has passed: the observer ran before `restore` returned, after the write.
        #expect(observed.map(\.event) == [RestoreEvent(itemIDs: [ids[0]])])
        #expect(observed.map(\.writes) == [1])

        // A restore that finds nothing writes nothing and reports nothing.
        #expect(!restorer.restore([ItemID(rawValue: "gone")], options: []))
        #expect(observed.count == 1)
    }

    // MARK: - History

    @Test func theRestoredItemsMoveToTheFrontWithTheFirstOneNewest() async throws {
        let ids = try await store.record(["a", "b", "c"])
        let restorer = makeRestorer(clockStartingAt: 1_000)

        #expect(restorer.restore([ids[0], ids[1]], options: []))
        // Still as captured: the history is updated after the paste, not as part of it.
        #expect(history == [ids[2], ids[1], ids[0]])
        await restorer.historyUpdate?.value

        #expect(history == [ids[0], ids[1], ids[2]])
        // Stamped last to first: "b" got the first reading of the clock, "a" the second.
        #expect(store.reader.items(ids).map(\.timestamp) == [.second(1_001), .second(1_000), .second(3)])
        #expect(store.reader.itemCount(in: .clipboard) == 3)
    }

    @Test func consecutiveRestoresReachTheHistoryInOrder() async throws {
        let ids = try await store.record(["a", "b", "c"])
        let restorer = makeRestorer()

        #expect(restorer.restore([ids[0]], options: []))
        #expect(restorer.restore([ids[1]], options: []))
        await restorer.historyUpdate?.value

        #expect(history == [ids[1], ids[0], ids[2]])
    }

    @Test func theTrimDeletesExpiredHistoryButNotPinnedOrRestoredItems() async throws {
        // Copied at seconds 1 to 4; the history keeps a month and the clock reads day 100.
        let ids = try await store.record(["a", "b", "c", "d"])
        try await store.writer.perform(author: .user) { context in
            try context.pin([ids[0]], to: try context.createPinboard(name: "Work", color: .blue))
        }
        let restorer = makeRestorer(clockStartingAt: 100 * 86_400)

        #expect(restorer.restore([ids[2]], options: []))
        await restorer.historyUpdate?.value

        #expect(history == [ids[2], ids[0]])
        #expect(store.reader.items(ids).map(\.id) == [ids[0], ids[2]])
        // The pinned item was as old as the ones that went, and was not even touched.
        #expect(store.reader.item(ids[0])?.timestamp == .second(1))
    }

    @Test func restoringAPinnedItemMovesItToTheFrontAndLeavesItOnItsPinboard() async throws {
        let ids = try await store.record(["a", "b"])
        let pinboard = try await store.writer.perform(author: .user) { context in
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.pin([ids[0]], to: pinboard)
            return pinboard
        }
        let restorer = makeRestorer(clockStartingAt: 1_000)

        #expect(restorer.restore([ids[0]], options: []))
        await restorer.historyUpdate?.value

        let item = try #require(store.reader.item(ids[0]))
        #expect(item.listID == pinboard)
        #expect(item.timestamp == .second(1_000))
        // The same item, not a copy of it, is what the history shows first.
        #expect(history == [ids[0], ids[1]])
        #expect(store.reader.itemCollection(for: pinboard).snapshot.ids == [ids[0]])
    }

    @Test func draggingOneItemCarriesWhatPastingItAloneWouldAndTouchesNothing() async throws {
        let ids = try await store.record(["a", "b"])
        let restorer = makeRestorer(clockStartingAt: 1_000)

        let contents = restorer.draggingContents(of: [ItemID(rawValue: "gone"), ids[0]], options: [])

        #expect(contents == [ids[0]: [PasteboardItemSnapshot.plainText("a").signed()]])
        #expect(pasteboard.writes.isEmpty)
        #expect(restorer.historyUpdate == nil)
        #expect(history == [ids[1], ids[0]])
    }

    @Test func draggingSeveralTextsMergesThemIntoTheFirstItemInTheOrderOfTheDrag() async throws {
        let ids = try await store.record(["a", "b", "c"])
        let restorer = makeRestorer(clockStartingAt: 1_000)

        let contents = restorer.draggingContents(of: [ids[2], ItemID(rawValue: "gone"), ids[0], ids[1]], options: .plainText)

        // The others travel as their identifier alone.
        #expect(contents == [
            ids[2]: [PasteboardItemSnapshot(["public.utf8-plain-text": Data("c\na\nb".utf8), "jnjambrino.Pasto": Data()])],
            ids[0]: [],
            ids[1]: [],
        ])
        #expect(pasteboard.writes.isEmpty)
        #expect(restorer.historyUpdate == nil)
    }

    @Test func restoringAnItemThatOnlyLivesOnAPinboardPutsItInTheHistory() async throws {
        let ids = try await store.record(["a", "b"])
        try await store.writer.perform(author: .user) { context in
            try context.pin([ids[0]], to: try context.createPinboard(name: "Work", color: .blue))
            try context.remove([ids[0]], from: .clipboard)
        }
        #expect(history == [ids[1]])
        let restorer = makeRestorer(clockStartingAt: 1_000)

        #expect(restorer.restore([ids[0]], options: []))
        await restorer.historyUpdate?.value

        #expect(history == [ids[0], ids[1]])
        #expect(store.reader.item(ids[0])?.listID != nil)
    }
}
