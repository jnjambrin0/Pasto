import Foundation
@testable import PastoCore
import Testing

struct IndexableTextTests {
    @Test func textJoinsTheStringOfEveryElement() {
        let items: [PasteboardItemSnapshot] = [.text("first"), .file("/tmp/a"), .text("second")]
        #expect(IndexableText.text(of: items, preview: .unknown, type: .text) == "first second")
        #expect(IndexableText.text(of: items, preview: .unknown, type: .unknown) == "first second")
    }

    @Test func textWithoutDataFallsBackToItsPreview() {
        let preview = ItemPreview.text(TextPreview(text: "kept", characterCount: 4))
        #expect(IndexableText.text(of: [], preview: preview, type: .text) == "kept")
        #expect(IndexableText.text(of: [], preview: preview, type: .unknown) == nil)
    }

    @Test func linkIsItsAddressAndThePageTitle() throws {
        let url = try #require(URL(string: "https://example.com/a"))
        let items = [PasteboardItemSnapshot.text("https://example.com/a")]
        #expect(IndexableText.text(of: items, preview: .link(LinkPreview(url: url)), type: .link) == "https://example.com/a")
        #expect(
            IndexableText.text(of: [], preview: .link(LinkPreview(url: url, title: "Example")), type: .link)
                == "https://example.com/a Example"
        )
    }

    @Test func colorIsWhatWasCopiedOrElseItsHexCode() {
        let preview = ItemPreview.color(ColorPreview(colorCode: 0x00FF7F))
        #expect(IndexableText.text(of: [.text("rgb(0, 255, 127)")], preview: preview, type: .color) == "rgb(0, 255, 127)")
        #expect(IndexableText.text(of: [], preview: preview, type: .color) == "#00FF7F")
    }

    @Test func filesAreTheirWholePaths() {
        let items: [PasteboardItemSnapshot] = [.file("/Users/me/Notes/a b.txt"), .file("/tmp/c.png")]
        #expect(IndexableText.text(of: items, preview: .unknown, type: .files) == "/Users/me/Notes/a b.txt /tmp/c.png")
        #expect(IndexableText.text(of: [], preview: .files(FilesPreview(paths: ["/x", ""])), type: .files) == "/x")
    }

    @Test func imagesAndEmptyTextsHaveNone() {
        #expect(IndexableText.text(of: [.text("caption")], preview: .unknown, type: .image) == nil)
        #expect(IndexableText.text(of: [.text("")], preview: .unknown, type: .unknown) == nil)
        #expect(IndexableText.text(of: [], preview: .unknown, type: .files) == nil)
    }
}
