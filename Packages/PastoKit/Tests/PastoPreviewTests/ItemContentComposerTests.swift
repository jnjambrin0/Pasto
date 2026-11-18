import AppKit
import PastoCore
import PastoCoreUI
import Testing
@testable import PastoPreview

/// What a save writes, and what the store makes of it.
@Suite struct ItemContentComposerTests {
    private let plainText = "public.utf8-plain-text"
    private let richText = "public.rtf"
    private let url = "public.url"
    private let urlName = "public.url-name"

    private func string(_ snapshot: PasteboardItemSnapshot, _ type: String) -> String? {
        snapshot.dataByType[type].flatMap { String(data: $0, encoding: .utf8) }
    }

    private func bold(_ string: String) -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
    }

    private func type(of snapshots: [PasteboardItemSnapshot]) async -> ItemType? {
        await NewItem.captured(from: snapshots, at: Date(timeIntervalSince1970: 0))?.type
    }

    // MARK: Text

    @Test func plainTextIsSavedAsItsCharactersOnly() {
        let snapshots = ItemContentComposer.text(NSAttributedString(string: "Hello\nworld"))
        #expect(snapshots.count == 1)
        #expect(snapshots[0].types == [plainText])
        #expect(string(snapshots[0], plainText) == "Hello\nworld")
    }

    @Test func coloursAndSizesAloneAreNotFormatting() {
        let text = NSAttributedString(string: "Hello", attributes: [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.red,
            .backgroundColor: NSColor.yellow,
        ])
        #expect(ItemContentComposer.text(text)[0].types == [plainText])
    }

    @Test func formattedTextIsSavedAsRichTextThenItsCharacters() throws {
        let snapshot = ItemContentComposer.text(bold("Hello"))[0]
        #expect(snapshot.types == [richText, plainText])
        #expect(string(snapshot, plainText) == "Hello")

        let saved = try #require(snapshot.dataByType[richText].flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) })
        #expect(saved.string == "Hello")
        #expect(TextTrait.bold.isActive(in: saved.attributes(at: 0, effectiveRange: nil)))
    }

    @Test func underlinedTextCountsAsFormatted() {
        let text = NSAttributedString(string: "Hello", attributes: [.underlineStyle: NSUnderlineStyle.single.rawValue])
        #expect(ItemContentComposer.text(text)[0].types == [richText, plainText])
    }

    @Test func editedTextIsDetectedAgain() async {
        #expect(await type(of: ItemContentComposer.text(NSAttributedString(string: "Hello"))) == .text)
        #expect(await type(of: ItemContentComposer.text(bold("Hello"))) == .text)
        // Text edited into an address or a colour code changes kind.
        #expect(await type(of: ItemContentComposer.text(NSAttributedString(string: "https://example.com"))) == .link)
        #expect(await type(of: ItemContentComposer.text(NSAttributedString(string: "#FF8800"))) == .color)
    }

    @Test func emptyTextHasNothingToStore() async {
        #expect(await type(of: ItemContentComposer.text(NSAttributedString())) == nil)
    }

    // MARK: Link

    @Test func linkIsSavedAsTextAddressAndTitle() async throws {
        let link = try #require(URL(string: "https://example.com/page?q=1"))
        let snapshots = ItemContentComposer.link(link, title: "Example")
        #expect(snapshots.count == 1)
        #expect(snapshots[0].types == [plainText, url, urlName])
        #expect(string(snapshots[0], plainText) == "https://example.com/page?q=1")
        #expect(string(snapshots[0], url) == "https://example.com/page?q=1")
        #expect(string(snapshots[0], urlName) == "Example")

        let item = try #require(await NewItem.captured(from: snapshots, at: Date(timeIntervalSince1970: 0)))
        #expect(item.type == .link)
        #expect(item.preview == .link(LinkPreview(url: link, title: "Example")))
    }

    // MARK: Image

    @Test func imageIsSavedInTheOneFormatItWasEncodedIn() async {
        let png = ItemContentComposer.image(.png(Data([1, 2, 3])))
        #expect(png.count == 1)
        #expect(png[0].types == ["public.png"])
        #expect(png[0].dataByType["public.png"] == Data([1, 2, 3]))
        #expect(await type(of: png) == .image)

        let jpeg = ItemContentComposer.image(.jpeg(Data([4, 5])))
        #expect(jpeg[0].types == ["public.jpeg"])
        #expect(await type(of: jpeg) == .image)
    }

    // MARK: Colour

    @Test func colourIsSavedAsItsHexadecimalText() async throws {
        let snapshots = ItemContentComposer.color(ColorCode(rawValue: 0xFF8800))
        #expect(snapshots.count == 1)
        #expect(snapshots[0].types == [plainText])
        #expect(string(snapshots[0], plainText) == "#FF8800")

        let item = try #require(await NewItem.captured(from: snapshots, at: Date(timeIntervalSince1970: 0)))
        #expect(item.type == .color)
        #expect(item.preview == .color(ColorPreview(colorCode: 0xFF8800)))
    }

    // MARK: New Text Item

    @Test func textThatIsOneAddressBecomesALink() async {
        let snapshots = ItemContentComposer.newTextItem(NSAttributedString(string: "  https://example.com/a \n"))
        #expect(snapshots.count == 1)
        #expect(snapshots[0].types == [plainText, url])
        #expect(string(snapshots[0], plainText) == "https://example.com/a")
        #expect(string(snapshots[0], url) == "https://example.com/a")
        #expect(await type(of: snapshots) == .link)
    }

    @Test func textAroundAnAddressStaysText() {
        let snapshot = ItemContentComposer.newTextItem(NSAttributedString(string: "see https://example.com"))[0]
        #expect(snapshot.types == [plainText])
        #expect(string(snapshot, plainText) == "see https://example.com")
    }

    @Test func mailAddressesStayText() {
        #expect(ItemContentComposer.wholeLink(in: "mailto:someone@example.com") == nil)
        #expect(ItemContentComposer.wholeLink(in: "someone@example.com") == nil)
        #expect(ItemContentComposer.newTextItem(NSAttributedString(string: "someone@example.com"))[0].types == [plainText])
    }

    @Test func newTextKeepsItsSpacesAndItsFormatting() {
        let plain = ItemContentComposer.newTextItem(NSAttributedString(string: "  note  "))[0]
        #expect(plain.types == [plainText])
        #expect(string(plain, plainText) == "  note  ")

        #expect(ItemContentComposer.newTextItem(bold("note"))[0].types == [richText, plainText])
    }
}
