import AppKit
import PastoCore
import PastoCoreUI
import Testing
@testable import PastoStack

@Suite struct StackCardContentTests {
    private func item(_ type: ItemType, _ preview: ItemPreview) -> Item {
        let date = Date(timeIntervalSinceReferenceDate: 0)
        return Item(id: ItemID(rawValue: "1"), type: type, preview: preview, timestamp: date, createdAt: date)
    }

    private func content(
        _ type: ItemType,
        _ preview: ItemPreview,
        isPlainText: Bool = false,
        isLinkPreviewsOn: Bool = true
    ) -> StackCardContent {
        StackCardContent(item: item(type, preview), isPlainText: isPlainText, isLinkPreviewsOn: isLinkPreviewsOn)
    }

    @Test func textKeepsItsFormattingUnlessTheStackPastesPlainText() throws {
        let formatted = NSAttributedString(string: "Hello", attributes: [.font: NSFont.boldSystemFont(ofSize: 20)])
        let rtf = try #require(formatted.rtf(from: NSRange(location: 0, length: formatted.length)))
        let preview = ItemPreview.text(TextPreview(text: "Hello", characterCount: 5, richTextData: rtf))

        guard case .rich(let text) = content(.text, preview).text else {
            Issue.record("Formatted text is shown without its formatting")
            return
        }
        #expect(text.string == "Hello")
        #expect((text.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize == 20)
        #expect(content(.text, preview, isPlainText: true) == StackCardContent(text: .plain("Hello")))
    }

    @Test func textWithoutFormattingIsStillATextCard() {
        // It is drawn on the background of a text card, which plain content does not get.
        #expect(content(.text, .text(TextPreview(text: "Hello", characterCount: 5)))
            == StackCardContent(text: .rich(NSAttributedString(string: "Hello"))))
    }

    @Test func aLinkShowsItsShortAddressAndTheSiteIconWhenPreviewsAreOn() throws {
        let url = try #require(URL(string: "https://www.example.com/page/"))
        let icon = Data([1, 2, 3])
        let link = ItemPreview.link(LinkPreview(url: url, title: "Example", iconData: icon))

        #expect(content(.link, link) == StackCardContent(text: .plain("example.com/page"), thumb: .icon(icon)))
        #expect(content(.link, link, isLinkPreviewsOn: false).thumb == .symbol("link"))
        #expect(content(.link, .link(LinkPreview(url: url))).thumb == .symbol("link"))
    }

    @Test func aColourShowsItsCodeNextToTheColour() {
        #expect(content(.color, .color(ColorPreview(colorCode: 0xFF8800)))
            == StackCardContent(text: .plain("#FF8800"), thumb: .color(ColorCode(rawValue: 0xFF8800))))
    }

    @Test func oneFileShowsItsPathAndSeveralTheirCount() {
        let one = FilesPreview(paths: ["/Users/someone/Report.pdf"])
        #expect(content(.files, .files(one)) == StackCardContent(text: .plain("/Users/someone/Report.pdf"), thumb: .symbol("doc")))

        let two = ItemPreview.files(FilesPreview(paths: ["/Users/someone/Report.pdf", "/tmp/Notes.txt"]))
        #expect(content(.files, two) == StackCardContent(text: .plain(ItemPresentation.typeName(of: item(.files, two))), thumb: .symbol("doc")))
    }

    @Test func anImageIsNamedByItsTypeNextToItsThumbnail() {
        let thumbnail = Data([9])
        let image = ItemPreview.image(ImagePreview(width: 10, height: 10, byteCount: 1, thumbnailData: thumbnail))
        #expect(content(.image, image) == StackCardContent(text: .plain(ItemPresentation.typeName(of: item(.image, image))), thumb: .image(thumbnail)))
        #expect(content(.image, .image(ImagePreview(width: 10, height: 10, byteCount: 1))).thumb == .symbol("photo"))
    }

    @Test func unknownContentHasNoThumb() {
        #expect(content(.unknown, .unknown) == StackCardContent(text: .plain(StackStrings.unknownContent)))
    }
}
