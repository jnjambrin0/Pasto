import Foundation
@testable import PastoCore
import PastoFoundation
import Testing

/// The capture pipeline end to end: a fake pasteboard on one side, an in-memory store on the other.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct HistoryManagerTests {
    private func capture(_ event: CaptureEvent?) throws -> PasteboardCapture {
        guard case .captured(let capture) = event else {
            throw UnexpectedEvent(event: event)
        }
        return capture
    }

    private struct UnexpectedEvent: Error {
        let event: CaptureEvent?
    }

    // MARK: - Capturing

    @Test func aCopyBecomesAnItem() async throws {
        let fixture = try await CaptureFixture()

        let capture = try capture(await fixture.copy("hola"))

        #expect(capture.itemType == .text)
        #expect(!capture.wasInHistory)
        let history = try await fixture.history()
        #expect(history.map(\.id) == [capture.itemID])
        let item = try #require(history.first)
        #expect(item.type == .text)
        #expect(item.preview == .text(TextPreview(text: "hola", characterCount: 4)))
        #expect(item.timestamp == fixture.clock.now())
        #expect(item.listID == nil)
        #expect(item.device?.name == "Test Mac")
    }

    @Test func theItemIsCreditedToTheApplicationInFront() async throws {
        let fixture = try await CaptureFixture()

        _ = try capture(await fixture.copy("hola"))

        let source = try #require(try await fixture.history().first?.sourceApplication)
        #expect(source.bundleIdentifier == "com.apple.Safari")
        #expect(source.name == "Safari")
        // The fixture's icon is plain red.
        #expect(source.colorCode == StoredColorCode.vividRed)
        #expect(source.iconData?.starts(with: [0x89, 0x50, 0x4E, 0x47]) == true)
    }

    @Test func anApplicationWithoutIconIsNotCredited() async throws {
        let fixture = try await CaptureFixture()
        fixture.applications.application = FrontmostApplication(bundleIdentifier: "com.example.cli", name: "cli", icon: nil)

        _ = try capture(await fixture.copy("hola"))

        #expect(try await fixture.history().first?.sourceApplication == nil)
    }

    @Test func everyKindOfContentIsClassified() async throws {
        let fixture = try await CaptureFixture()
        let png = TestImage.encoded(TestImage.solid(.red, width: 20, height: 10, hasAlpha: false))

        #expect(try capture(await fixture.copy("https://ejemplo.com")).itemType == .link)
        #expect(try capture(await fixture.copy("#1A2B3C")).itemType == .color)
        #expect(try capture(await fixture.copy([.file("/tmp/a.txt")])).itemType == .files)
        #expect(try capture(await fixture.copy([PasteboardItemSnapshot(["public.png": png])])).itemType == .image)
        #expect(try capture(await fixture.copy([PasteboardItemSnapshot(strings: ["com.example.private": "x"])])).itemType == .unknown)

        #expect(Set(try await fixture.history().map(\.type)) == [.unknown, .image, .files, .color, .link])
    }

    @Test func copyingTheSameAgainMovesTheItemToTheFront() async throws {
        let fixture = try await CaptureFixture()
        let first = try capture(await fixture.copy("a"))
        fixture.clock.advance(days: 1)
        let second = try capture(await fixture.copy("b"))
        fixture.clock.advance(days: 1)

        let again = try capture(await fixture.copy("a"))

        #expect(again == PasteboardCapture(itemID: first.itemID, itemType: .text, wasInHistory: true, didChangeNewestItem: true))
        let history = try await fixture.history()
        #expect(history.map(\.id) == [first.itemID, second.itemID])
        #expect(history.first?.timestamp == fixture.clock.now())
    }

    @Test func theSameLinkWithAndWithoutTrailingSlashIsOneItem() async throws {
        let fixture = try await CaptureFixture()
        let first = try capture(await fixture.copy("https://ejemplo.com"))

        let again = try capture(await fixture.copy("https://ejemplo.com/"))

        #expect(again.itemID == first.itemID)
        #expect(again.wasInHistory)
        #expect(try await fixture.history().count == 1)
    }

    @Test func contentThatOnlyLivesOnAPinboardEntersTheHistoryAndStaysPinned() async throws {
        let fixture = try await CaptureFixture()
        let pinned = try capture(await fixture.copy("a"))
        let pinboard = try await fixture.store.writer.perform(author: .user) { context in
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.pin([pinned.itemID], to: pinboard)
            try context.remove([pinned.itemID], from: .clipboard)
            return pinboard
        }
        #expect(try await fixture.history().isEmpty)

        let again = try capture(await fixture.copy("a"))

        // The same item, which the history now shows first. It was not in the history before.
        #expect(again == PasteboardCapture(itemID: pinned.itemID, itemType: .text, wasInHistory: false, didChangeNewestItem: true))
        let history = try await fixture.history()
        #expect(history.map(\.id) == [pinned.itemID])
        #expect(history.first?.listID == pinboard)
    }

    @Test func theChangeTokenAndTheReadCountArePersisted() async throws {
        let fixture = try await CaptureFixture()

        _ = try capture(await fixture.copy("a"))
        _ = try capture(await fixture.copy("b"))

        #expect(fixture.config.value(for: .pasteboardChangeToken) == fixture.source.changeCount)
        #expect(fixture.config.value(for: .pasteboardSyncCount) == 2)
    }

    // MARK: - What is not captured

    @Test func whatWasOnThePasteboardBeforeStartingIsNotCaptured() async throws {
        let fixture = try await CaptureFixture(starts: false)
        fixture.source.copy([.text("old")])
        await fixture.start()

        _ = try capture(await fixture.copy("new"))

        #expect(try await fixture.history().map(\.preview) == [.text(TextPreview(text: "new", characterCount: 3))])
    }

    @Test func copiesFromAnIgnoredApplicationAreNotCaptured() async throws {
        let fixture = try await CaptureFixture()
        fixture.applications.application = FrontmostApplication(
            bundleIdentifier: "com.1password.1password", name: "1Password", icon: CaptureFixture.safari.icon
        )
        await fixture.copyWithoutCapture([.text("hunter2")])
        #expect(try await fixture.history().isEmpty)

        // The veto leaves nothing behind: the next copy from elsewhere is captured as usual.
        fixture.applications.application = CaptureFixture.safari
        let capture = try capture(await fixture.copy("hola"))

        #expect(try await fixture.history().map(\.id) == [capture.itemID])
        #expect(fixture.source.requestedTypes == ["public.utf8-plain-text"])
    }

    @Test func aReadOfSeveralChangesThatLeavesTheNewestItemAsItWasIsNotAnnounced() async throws {
        let fixture = try await CaptureFixture()
        let first = try capture(await fixture.copy("a"))
        fixture.applications.application = FrontmostApplication(
            bundleIdentifier: "com.1password.1password", name: "1Password", icon: CaptureFixture.safari.icon
        )
        await fixture.copyWithoutCapture([.text("hunter2")])
        fixture.applications.application = CaptureFixture.safari

        // This read stands for the vetoed copy too, and "a" stays the newest item: it is
        // recorded, but nobody hears of it. The next capture is the first news.
        await fixture.copyWithoutCapture([.text("a")])
        let next = try capture(await fixture.copy("b"))

        #expect(next.itemID != first.itemID)
        #expect(try await fixture.history().count == 2)
    }

    @Test func theUsersIgnoredApplicationsAreHonoured() async throws {
        let fixture = try await CaptureFixture()
        fixture.config.set(["com.apple.Safari"], for: .ignoredBundleIdentifiers)

        await fixture.copyWithoutCapture([.text("hola")])

        #expect(try await fixture.history().isEmpty)
    }

    @Test func contentMarkedAsConcealedIsNotCaptured() async throws {
        let fixture = try await CaptureFixture()

        await fixture.copyWithoutCapture([
            PasteboardItemSnapshot(strings: ["public.utf8-plain-text": "hunter2", "org.nspasteboard.ConcealedType": ""]),
        ])

        #expect(try await fixture.history().isEmpty)
        #expect(fixture.source.requestedTypes.isEmpty)
    }

    @Test func nothingIsCapturedWithoutAnApplicationInFront() async throws {
        let fixture = try await CaptureFixture()
        fixture.applications.application = nil

        await fixture.copyWithoutCapture([.text("hola")])

        #expect(try await fixture.history().isEmpty)
    }

    @Test func pastosOwnWritesAreNotCaptured() async throws {
        let fixture = try await CaptureFixture()

        let changeCount = fixture.pasteboard.write([.text("pasted")])
        #expect(changeCount == fixture.source.changeCount)
        #expect(fixture.pasteboard.changeToken == changeCount)

        let capture = try capture(await fixture.copy("copied"))
        #expect(try await fixture.history().map(\.id) == [capture.itemID])
        #expect(fixture.config.value(for: .pasteboardSyncCount) == 1)
    }

    @Test func aMissingPermissionIsReportedInsteadOfReading() async throws {
        let fixture = try await CaptureFixture()
        fixture.source.setAllowsProgrammaticReads(false)

        #expect(await fixture.copy("hola") == .pasteboardAccessNeeded)

        #expect(fixture.source.requestedTypes.isEmpty)
        #expect(try await fixture.history().isEmpty)
    }

    @Test func aPasteboardThatFillsUpAfterBeingClearedIsCaptured() async throws {
        let fixture = try await CaptureFixture()
        // The application clears the pasteboard first…
        await fixture.copyWithoutCapture([])
        // …and writes a moment later, without the change count moving.
        fixture.source.fill([.text("late")])

        let capture = try capture(await fixture.nextEvent())

        #expect(capture.itemType == .text)
        #expect(try await fixture.history().count == 1)
    }

    // MARK: - Pause

    @Test func nothingCopiedWhilePausedIsCaptured() async throws {
        let fixture = try await CaptureFixture()
        await fixture.manager.setPaused(true)
        #expect(await fixture.manager.isPaused)
        // A poll that was already running when capture paused is over by now.
        fixture.waitForPasteboardQueue()
        fixture.source.copy([.text("while paused")])

        await fixture.manager.setPaused(false)
        fixture.waitForPasteboardQueue()
        let capture = try capture(await fixture.copy("after"))

        #expect(try await fixture.history().map(\.id) == [capture.itemID])
    }

    @Test func aManagerPausedBeforeStartingStaysPaused() async throws {
        let fixture = try await CaptureFixture(starts: false)
        await fixture.manager.setPaused(true)
        await fixture.start()
        fixture.source.copy([.text("while paused")])

        await fixture.manager.setPaused(false)
        fixture.waitForPasteboardQueue()
        let capture = try capture(await fixture.copy("after"))

        #expect(try await fixture.history().map(\.id) == [capture.itemID])
    }

    // MARK: - Retention

    @Test func itemsOlderThanTheCapacityExpireWhenSomethingIsCaptured() async throws {
        let fixture = try await CaptureFixture()
        let pinned = try capture(await fixture.copy("pinned"))
        try await fixture.store.writer.perform(author: .user) { context in
            let pinboard = try context.createPinboard(name: "Work", color: .blue)
            try context.pin([pinned.itemID], to: pinboard)
        }
        _ = try capture(await fixture.copy("old"))
        fixture.clock.advance(days: 29)
        let recent = try capture(await fixture.copy("recent"))
        fixture.clock.advance(days: 2)

        // The history keeps a month by default: "old" is 31 days old now, "recent" two.
        let new = try capture(await fixture.copy("new"))

        // Items on a pinboard never expire, and stay in the history as well.
        #expect(try await fixture.history().map(\.id) == [new.itemID, recent.itemID, pinned.itemID])
        let pinnedSurvives = try await fixture.store.writer.perform(author: .maintenance) { context in
            (try? context.item(pinned.itemID)) != nil
        }
        #expect(pinnedSurvives)
    }

    @Test func copyingAnExpiredItemAgainKeepsIt() async throws {
        let fixture = try await CaptureFixture()
        let old = try capture(await fixture.copy("old"))
        fixture.clock.advance(days: 40)

        let again = try capture(await fixture.copy("old"))

        #expect(again == PasteboardCapture(itemID: old.itemID, itemType: .text, wasInHistory: true, didChangeNewestItem: false))
        #expect(try await fixture.history().map(\.id) == [old.itemID])
    }

    @Test func theCapacityOfTheHistoryDecidesWhatExpires() async throws {
        let fixture = try await CaptureFixture()
        try await fixture.setCapacity(.day)
        _ = try capture(await fixture.copy("yesterday"))
        fixture.clock.advance(days: 1.5)
        let today = try capture(await fixture.copy("today"))
        #expect(try await fixture.history().map(\.id) == [today.itemID])

        try await fixture.setCapacity(.unlimited)
        fixture.clock.advance(days: 4000)
        let muchLater = try capture(await fixture.copy("much later"))
        #expect(try await fixture.history().map(\.id) == [muchLater.itemID, today.itemID])
    }

    @Test(arguments: [
        (HistoryCapacity.day, 1.0),
        (.week, 7),
        (.month, 30),
        (.year, 365),
    ])
    func theCutoffIsTheCapacityInDaysBeforeNow(capacity: HistoryCapacity, days: Double) {
        let now = Date(timeIntervalSinceReferenceDate: 800_000_000)

        #expect(HistoryRetention.cutoff(for: capacity, at: now) == now.addingTimeInterval(-days * 86_400))
        #expect(HistoryRetention.cutoff(for: .unlimited, at: now) == nil)
    }
}
