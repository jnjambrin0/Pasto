import AppKit
import PastoCore
import Testing
@testable import PastoCoreUI

@Suite struct ItemCellModelTests {
    static let english = CardStrings(languageCode: "en")!
    static let copied = Date(timeIntervalSinceReferenceDate: 800_000_000)

    func item(
        _ type: ItemType = .text,
        _ preview: ItemPreview = .text(TextPreview(text: "hello", characterCount: 5)),
        title: String? = nil,
        listID: ListID? = nil,
        source: PastoCore.SourceApplication? = nil
    ) -> Item {
        Item(
            id: ItemID(rawValue: "item"), type: type, title: title, preview: preview,
            timestamp: Self.copied, createdAt: Self.copied, listID: listID, sourceApplication: source
        )
    }

    func model(_ item: Item, _ context: ItemCellContext = ItemCellContext(collection: .history)) -> ItemCellModel {
        ItemCellModel(item: item, context: context, strings: Self.english)
    }

    func pinboard(_ color: PinboardColor) -> ClipList {
        ClipList(id: ListID(rawValue: "board"), name: "Board", type: .pinboard, attributes: .pinboard(color: color), index: 1)
    }

    // MARK: - Header

    @Test func titleIsTheCustomOneOrTheTypeName() {
        #expect(model(item()).title == "Text")
        #expect(model(item(title: "")).title == "Text")
        #expect(model(item(title: "Shopping list")).title == "Shopping list")
        #expect(model(item(title: "Shopping list")).typeName == "Text")
    }

    @Test func typeNames() {
        let url = URL(string: "https://example.com")!
        #expect(model(item(.link, .link(LinkPreview(url: url)))).typeName == "Link")
        #expect(model(item(.image, .image(ImagePreview(width: 1, height: 1, byteCount: 1)))).typeName == "Image")
        #expect(model(item(.color, .color(ColorPreview(colorCode: 0xFF9500)))).typeName == "Color")
        #expect(model(item(.unknown, .unknown)).typeName == "Unknown")
        #expect(model(item(.files, .files(FilesPreview(paths: ["/a"])))).typeName == "File")
        #expect(model(item(.files, .files(FilesPreview(paths: ["/a", "/b", "/c"])))).typeName == "3 files")
        // A file item whose preview is missing counts as one file.
        #expect(model(item(.files, .unknown)).typeName == "File")
    }

    @Test func dateIsTheItemsTimestamp() {
        #expect(model(item()).date == Self.copied)
    }

    @Test func dateShowsOutsidePinboards() {
        let pinned = item(listID: ListID(rawValue: "board"))
        let board = pinboard(.blue)
        #expect(model(item(), ItemCellContext(collection: .history)).showsDate)
        #expect(model(item(), ItemCellContext(collection: .picks)).showsDate)
        #expect(model(item(), ItemCellContext(collection: .search)).showsDate)
        #expect(!model(pinned, ItemCellContext(collection: .pinboard, pinboard: board)).showsDate)
        #expect(!model(pinned, ItemCellContext(collection: .search, pinboard: board)).showsDate)
    }

    @Test func pinnedItemsTakeThePinboardsColor() {
        let pinned = item(listID: ListID(rawValue: "board"))
        #expect(model(item()).pinboardColor == nil)
        #expect(model(item(listID: .clipboard)).pinboardColor == nil)
        #expect(model(pinned, ItemCellContext(collection: .pinboard, pinboard: pinboard(.purple))).pinboardColor == .purple)
        // The caller did not look the pinboard up: still pinned, in the neutral colour.
        #expect(model(pinned, ItemCellContext(collection: .search)).pinboardColor == .gray)
    }

    @Test func sourceApplication() {
        let icon = Data([1, 2, 3])
        let known = PastoCore.SourceApplication(bundleIdentifier: "a", name: "Notes", colorCode: 0xFFFA_B700, iconData: icon)
        let uncolored = PastoCore.SourceApplication(bundleIdentifier: "b", name: "Tool")

        #expect(model(item()).sourceApplication == nil)
        #expect(model(item(source: known)).sourceApplication
            == ItemCellModel.SourceApplication(name: "Notes", iconData: icon, color: ColorCode(rawValue: 0xFFFA_B700)))
        #expect(model(item(source: uncolored)).sourceApplication == ItemCellModel.SourceApplication(name: "Tool"))
    }

    @Test func quickPasteIndex() {
        #expect(model(item(), ItemCellContext(collection: .history, quickPasteIndex: 4)).quickPasteIndex == 4)
        #expect(model(item()).quickPasteIndex == nil)
        #expect(ItemCellModel.quickPasteIndex(forCellAt: 0) == 1)
        #expect(ItemCellModel.quickPasteIndex(forCellAt: 8) == 9)
        #expect(ItemCellModel.quickPasteIndex(forCellAt: 9) == nil)
        #expect(ItemCellModel.quickPasteIndex(forCellAt: -1) == nil)
    }

    // MARK: - Content

    @Test func plainText() throws {
        let text = try #require(textContent(of: model(item(.text, .text(TextPreview(text: "a\nb", characterCount: 1200))))))
        #expect(text.attributedText.string == "a\nb")
        #expect(text.characterCount == 1200)
        #expect(text.background == .plain)
    }

    @Test func richTextKeepsItsAttributes() throws {
        let rtf = #"{\rtf1\ansi{\fonttbl{\f0\fswiss Helvetica;}}{\colortbl;\red255\green149\blue0;}\f0\fs28 plain {\b bold} {\cf1 orange}}"#
        let preview = TextPreview(text: "plain bold orange", characterCount: 17, richTextData: Data(rtf.utf8))
        let text = try #require(textContent(of: model(item(.text, .text(preview)))))

        #expect(text.attributedText.string == "plain bold orange")
        #expect(!text.background.isPlain)
        let font = text.attributedText.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.pointSize == 14)
    }

    @Test func unreadableRichTextFallsBackToThePlainText() throws {
        let preview = TextPreview(text: "plain", characterCount: 5, richTextData: Data([0, 1, 2, 3]))
        let text = try #require(textContent(of: model(item(.text, .text(preview)))))
        #expect(text.attributedText.string == "plain")
        #expect(text.background == .plain)
    }

    @Test func longTextIsCutAtTheLayoutLimit() throws {
        let long = String(repeating: "x", count: 30000)
        let text = try #require(textContent(of: model(item(.text, .text(TextPreview(text: long, characterCount: 30000))))))
        #expect(text.attributedText.length == 20000)
        #expect(text.characterCount == 30000)
    }

    @Test func linkReadsTheSizeOfItsImage() throws {
        let url = URL(string: "https://www.apple.com/macos/")!
        let preview = LinkPreview(url: url, title: "macOS", iconData: Data([9]), imageData: try png(width: 6, height: 4))
        guard case .link(let link) = model(item(.link, .link(preview))).content else {
            Issue.record("expected a link")
            return
        }
        #expect(link.url == url)
        #expect(link.title == "macOS")
        #expect(link.iconData == Data([9]))
        #expect(link.image?.pixelWidth == 6)
        #expect(link.image?.pixelHeight == 4)
        #expect(link.image?.isSquare == false)
    }

    @Test func linkIgnoresImageDataThatIsNotAnImage() {
        let preview = LinkPreview(url: URL(string: "https://example.com")!, imageData: Data([1, 2, 3]))
        guard case .link(let link) = model(item(.link, .link(preview))).content else {
            Issue.record("expected a link")
            return
        }
        #expect(link.image == nil)
    }

    @Test func imageColorAndFiles() {
        let thumbnail = Data([7])
        let image = ImagePreview(width: 640, height: 400, byteCount: 10, thumbnailData: thumbnail)
        #expect(model(item(.image, .image(image))).content
            == .image(ItemCellModel.Image(width: 640, height: 400, thumbnailData: thumbnail)))
        #expect(model(item(.color, .color(ColorPreview(colorCode: 0x34C759)))).content == .color(ColorCode(rawValue: 0x34C759)))
        #expect(model(item(.files, .files(FilesPreview(paths: ["/a", "/b"], totalByteCount: 9)))).content
            == .files(ItemCellModel.Files(paths: ["/a", "/b"])))
    }

    /// The preview is what a card can draw, so it picks the card; the item's type names it.
    @Test func previewDecidesTheCardWhenItDisagreesWithTheType() {
        let missing = model(item(.text, .unknown))
        #expect(missing.type == .unknown)
        #expect(missing.content == .unknown)
        #expect(missing.typeName == "Text")

        let mismatched = model(item(.link, .text(TextPreview(text: "https://example.com", characterCount: 19))))
        #expect(mismatched.type == .text)
        #expect(mismatched.typeName == "Link")
    }

    // MARK: - Helpers

    private func textContent(of model: ItemCellModel) -> ItemCellModel.Text? {
        if case .text(let text) = model.content { text } else { nil }
    }

    private func png(width: Int, height: Int) throws -> Data {
        let bitmap = try #require(NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
        ))
        return try #require(bitmap.representation(using: .png, properties: [:]))
    }
}
