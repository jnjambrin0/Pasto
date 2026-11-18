import CoreGraphics
import Foundation
import PastoCore
import PastoFoundation
import Testing

/// The welcome content as the store keeps it: notes in the history, a pinboard of a note and
/// links, all credited to the app.
@MainActor
@Suite(.timeLimit(.minutes(1)))
struct WelcomeContentTests {
    private let store: StoreFixture

    init() throws {
        store = try StoreFixture()
    }

    private static let site = URL(string: "https://example.com")!
    private static let help = URL(string: "https://example.com/help")!

    private static func content(application: FrontmostApplication? = application()) -> WelcomeContent {
        WelcomeContent(
            historyEntries: [
                .note(title: "First", text: "Newest note"),
                .note(title: "Second", text: "Middle note"),
                .note(title: "Third", text: "Oldest note"),
            ],
            pinboardName: "Links",
            pinboardColor: .red,
            pinboardEntries: [
                .note(title: "Hello", text: "About these links"),
                .link(title: "Site", url: site, pageTitle: "The site"),
                .link(title: "Help", url: help, pageTitle: "Get help"),
            ],
            application: application
        )
    }

    /// An application with a 128-pixel icon of one colour.
    private static func application() -> FrontmostApplication {
        let context = CGContext(
            data: nil, width: 128, height: 128, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 0.2, green: 0.5, blue: 0.8, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        return FrontmostApplication(bundleIdentifier: "com.example.app", name: "Example", icon: context.makeImage())
    }

    private func seed(_ content: WelcomeContent = content()) async throws -> Bool {
        try await store.writer.perform(author: .maintenance) { try $0.seedWelcomeContent(content) }
    }

    private var history: [Item] {
        store.reader.items(store.reader.itemCollection(for: .clipboard).snapshot.ids)
    }

    private var pinboard: ClipList? {
        store.reader.lists().first { $0.type == .pinboard }
    }

    private func items(on list: ListID) -> [Item] {
        store.reader.items(store.reader.itemCollection(for: list).snapshot.ids)
    }

    @Test func theHistoryShowsTheNotesInTheGivenOrderAndOnlyThere() async throws {
        #expect(try await seed())

        #expect(history.map(\.title) == ["First", "Second", "Third"])
        #expect(history.map(\.type) == [.text, .text, .text])
        #expect(history.allSatisfy { $0.listID == nil })
        #expect(history.first?.timestamp == StoreFixture.now)
        #expect(history.allSatisfy { $0.createdAt == StoreFixture.now })
        guard case .text(let preview) = history.first?.preview else {
            Issue.record("The note has no text preview")
            return
        }
        #expect(preview.text == "Newest note")
        #expect(store.reader.pasteboardItems(for: history[0].id)?.first?.plainText == "Newest note")
    }

    @Test func thePinboardComesAfterTheHistoryWithItsItemsInOrderAndOnlyThere() async throws {
        #expect(try await seed())

        let pinboard = try #require(pinboard)
        #expect(pinboard.name == "Links")
        #expect(pinboard.attributes == .pinboard(color: .red))
        #expect(store.reader.lists().map(\.id) == [.clipboard, pinboard.id])

        let items = items(on: pinboard.id)
        #expect(items.map(\.title) == ["Hello", "Site", "Help"])
        #expect(items.map(\.type) == [.text, .link, .link])
        #expect(items.map(\.displayOrderInPinboard) == [0, 1, 2])
        #expect(items.allSatisfy { $0.timestamp == nil })
        #expect(history.count == 3)
    }

    @Test func linksCarryTheirPreviewWithTheApplicationIcon() async throws {
        #expect(try await seed())

        let pinboard = try #require(pinboard)
        let link = try #require(items(on: pinboard.id).first { $0.type == .link })
        guard case .link(let preview) = link.preview else {
            Issue.record("The link has no link preview")
            return
        }
        #expect(preview.url == Self.site)
        #expect(preview.title == "The site")
        #expect(preview.iconData != nil)
        #expect(preview.iconData == link.sourceApplication?.iconData)
        #expect(preview.imageData == nil)

        let snapshot = try #require(store.reader.pasteboardItems(for: link.id)?.first)
        #expect(snapshot.types == ["public.utf8-plain-text", "public.url", "public.url-name"])
        #expect(snapshot.plainText == "https://example.com")
        #expect(snapshot.dataByType["public.url-name"] == Data("The site".utf8))
    }

    @Test func everyItemIsCreditedToTheApplicationOnThisMac() async throws {
        #expect(try await seed())

        let all = history + items(on: try #require(pinboard).id)
        #expect(all.count == 6)
        #expect(all.allSatisfy { $0.sourceApplication?.bundleIdentifier == "com.example.app" })
        #expect(all.allSatisfy { $0.sourceApplication?.name == "Example" })
        #expect(all.allSatisfy { $0.sourceApplication?.colorCode != 0 })
        #expect(all.allSatisfy { $0.device?.name == "Test Mac" })
    }

    @Test func withoutAnApplicationTheItemsHaveNoSourceAndTheLinksNoIcon() async throws {
        #expect(try await seed(Self.content(application: nil)))

        let all = history + items(on: try #require(pinboard).id)
        #expect(all.allSatisfy { $0.sourceApplication == nil })
        for item in all {
            if case .link(let preview) = item.preview { #expect(preview.iconData == nil) }
        }
    }

    @Test func aStoreWithAPinboardGetsNothing() async throws {
        let ids = try await store.record(["mine"])
        let mine = try await store.writer.perform(author: .user) { try $0.createPinboard(name: "Mine", color: .blue) }

        #expect(try await seed() == false)

        #expect(store.reader.lists().map(\.id) == [.clipboard, mine])
        #expect(history.map(\.id) == ids)
    }

    @Test func aHistoryWithoutPinboardsStillGetsIt() async throws {
        let ids = try await store.record(["mine"])

        #expect(try await seed())

        #expect(history.count == 4)
        #expect(history.first?.title == "First")
        #expect(history.last?.id == ids[0])
    }

    @Test func seedingAgainAddsNothing() async throws {
        #expect(try await seed())
        #expect(try await seed() == false)

        #expect(history.count == 3)
        #expect(store.reader.lists().count == 2)
    }

    @Test func theItemsGoLikeAnyOther() async throws {
        #expect(try await seed())
        let pinboard = try #require(pinboard)
        let notes = history.map(\.id)

        try await store.writer.perform(author: .user) { try $0.remove(notes, from: .clipboard) }
        try await store.writer.perform(author: .user) { try $0.deleteList(pinboard.id) }

        #expect(history.isEmpty)
        #expect(store.reader.lists().map(\.id) == [.clipboard])
        #expect(store.reader.items(notes).isEmpty)
    }

    @Test func copyingTheSameNoteLaterFindsTheSeededItem() async throws {
        #expect(try await seed())
        let seeded = try #require(history.last)
        let copy = try #require(await NewItem.captured(
            from: [PasteboardItemSnapshot(
                types: ["public.utf8-plain-text"],
                dataByType: ["public.utf8-plain-text": Data("Oldest note".utf8)]
            )],
            at: .second(2_000_000)
        ))

        let outcome = try await store.writer.perform(author: .capture) { try $0.record(copy) }

        #expect(outcome.id == seeded.id)
        #expect(outcome.kind == .movedToFront)
    }
}
