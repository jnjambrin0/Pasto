import AppKit
import CoreGraphics
import Foundation
@testable import PastoCore
import Testing

struct ImageThumbnailTests {
    private static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
    private static let jpegSignature: [UInt8] = [0xFF, 0xD8, 0xFF]

    private func size(_ width: CGFloat, _ height: CGFloat) -> CGSize {
        CGSize(width: width, height: height)
    }

    // MARK: - Size

    @Test func anImageThatFitsKeepsItsPixels() {
        #expect(ImageThumbnail.thumbnailPixelSize(pixelSize: size(200, 100), pointSize: size(200, 100)) == size(200, 100))
        #expect(ImageThumbnail.thumbnailPixelSize(pixelSize: size(280, 230), pointSize: size(280, 230)) == size(280, 230))
        // A 2× image is measured in points.
        #expect(ImageThumbnail.thumbnailPixelSize(pixelSize: size(560, 460), pointSize: size(280, 230)) == size(560, 460))
    }

    @Test func aLargerImageIsReducedToFitKeepingItsProportions() {
        #expect(ImageThumbnail.thumbnailPixelSize(pixelSize: size(4000, 3000), pointSize: size(4000, 3000)) == size(560, 420))
        #expect(ImageThumbnail.thumbnailPixelSize(pixelSize: size(1000, 4600), pointSize: size(1000, 4600)) == size(100, 460))
        #expect(ImageThumbnail.thumbnailPixelSize(pixelSize: size(5600, 200), pointSize: size(2800, 100)) == size(560, 20))
    }

    @Test func aThumbnailNeverHasMorePixelsThanItsImage() {
        // 300 × 300 points do not fit, but the image has no pixels to spare for a 2× thumbnail.
        #expect(ImageThumbnail.thumbnailPixelSize(pixelSize: size(300, 300), pointSize: size(300, 300)) == size(300, 300))
    }

    // MARK: - Format

    @Test func anOpaqueImageIsStoredAsJPEG() {
        #expect(ImageThumbnail.format(for: TestImage.solid(.red, width: 64, height: 64, hasAlpha: false)) == .jpeg)
        // An alpha channel with nothing transparent in it changes nothing.
        #expect(ImageThumbnail.format(for: TestImage.solid(.red, width: 64, height: 64)) == .jpeg)
    }

    @Test func aTransparentImageIsStoredAsPNG() {
        let halfTransparent = TestImage.make(width: 64, height: 64) { x, _ in x < 32 ? .clear : .red }

        #expect(ImageThumbnail.format(for: halfTransparent) == .png)
    }

    @Test func aLittleTransparencyIsNotEnough() {
        // One corner, about 1 % of the image.
        let roundedCorner = TestImage.make(width: 320, height: 320) { x, y in x < 30 && y < 30 ? .clear : .red }

        #expect(ImageThumbnail.format(for: roundedCorner) == .jpeg)
    }

    @Test func transparentPixelsInAnImageWithoutAlphaChannelDoNotCount() {
        let image = TestImage.make(width: 64, height: 64, hasAlpha: false) { _, _ in .clear }

        #expect(!ImageThumbnail.isTransparent(image))
    }

    // MARK: - Preview

    @Test func thePreviewOfASmallImageIsTheImageItself() throws {
        let data = TestImage.encoded(TestImage.solid(.red, width: 120, height: 80, hasAlpha: false))

        let preview = try #require(ImageThumbnail.preview(of: data))

        #expect(preview.width == 120)
        #expect(preview.height == 80)
        #expect(preview.byteCount == data.count)
        let thumbnail = try #require(preview.thumbnailData)
        #expect(thumbnail.starts(with: Self.jpegSignature))
        #expect(TestImage.pixelSize(of: thumbnail) == size(120, 80))
    }

    @Test func thePreviewOfALargeImageIsReduced() throws {
        let image = TestImage.make(width: 1400, height: 460) { x, _ in x < 700 ? .clear : .red }
        let data = TestImage.encoded(image)

        let preview = try #require(ImageThumbnail.preview(of: data))

        #expect(preview.width == 1400)
        #expect(preview.height == 460)
        let thumbnail = try #require(preview.thumbnailData)
        #expect(thumbnail.starts(with: Self.pngSignature))
        #expect(TestImage.pixelSize(of: thumbnail) == size(560, 184))
    }

    @Test func thePreviewStatesTheSizeInPoints() throws {
        // A Retina screenshot: twice as many pixels as points.
        let image = TestImage.solid(.red, width: 1600, height: 1200, hasAlpha: false)
        let data = TestImage.encoded(image, dotsPerInch: 144)

        let preview = try #require(ImageThumbnail.preview(of: data))

        #expect(preview.width == 800)
        #expect(preview.height == 600)
    }

    @Test func dataThatIsNotAnImageHasNoPreview() {
        #expect(ImageThumbnail.preview(of: Data("not an image".utf8)) == nil)
    }
}

struct ItemPreviewBuilderTests {
    @Test func shortTextIsKeptAsCopiedWithItsLength() async {
        let preview = await ItemPreviewBuilder.preview(of: [.text("  hola\n")], type: .text)

        #expect(preview == .text(TextPreview(text: "  hola\n", characterCount: 7)))
    }

    @Test func longTextIsCutAtTheLimitAndKeepsItsFullLength() async {
        let text = String(repeating: "a", count: 499) + "😀" + String(repeating: "b", count: 100)

        let preview = await ItemPreviewBuilder.preview(of: [.text(text)], type: .text)

        // The emoji straddles the limit (units 499 and 500), so the cut falls before it.
        #expect(preview == .text(TextPreview(text: String(repeating: "a", count: 499), characterCount: 601)))
        #expect(ItemPreviewBuilder.truncated(String(repeating: "a", count: 500)).utf16.count == 500)
        #expect(ItemPreviewBuilder.truncated(String(repeating: "a", count: 501)).utf16.count == 500)
    }

    @Test func formattedTextKeepsItsFormatting() async throws {
        let rtf = "{\\rtf1\\ansi{\\b hola}}"
        let item = PasteboardItemSnapshot(strings: ["public.rtf": rtf, "public.utf8-plain-text": "hola"])

        let preview = await ItemPreviewBuilder.preview(of: [item], type: .text)

        guard case .text(let text) = preview, let data = text.richTextData else {
            Issue.record("Expected a text preview with formatted text")
            return
        }
        #expect(text.text == "hola")
        let formatted = try #require(NSAttributedString(rtf: data, documentAttributes: nil))
        #expect(formatted.string == "hola")
        let font = formatted.attribute(.font, at: 0, effectiveRange: nil) as? NSFont
        #expect(font?.fontDescriptor.symbolicTraits.contains(.bold) == true)
    }

    @Test func formattedTextIsWhatTheItemIsPreviewedAndMeasuredBy() async throws {
        // The string and the formatted text of one copy need not agree.
        let rtf = "{\\rtf1\\ansi hola mundo}"
        let item = PasteboardItemSnapshot(strings: ["public.rtf": rtf, "public.utf8-plain-text": "hola"])

        let preview = await ItemPreviewBuilder.preview(of: [item], type: .text)

        guard case .text(let text) = preview else {
            Issue.record("Expected a text preview")
            return
        }
        #expect(text.text == "hola mundo")
        #expect(text.characterCount == 10)
    }

    @Test func htmlAloneIsNotConverted() async {
        let item = PasteboardItemSnapshot(strings: ["public.html": "<b>hola</b>", "public.utf8-plain-text": "hola"])

        #expect(await ItemPreviewBuilder.preview(of: [item], type: .text) == .text(TextPreview(text: "hola", characterCount: 4)))
    }

    @Test func aLinkTakesItsTitleFromTheNameItWasCopiedWith() async throws {
        let item = PasteboardItemSnapshot(strings: [
            "public.url": "https://ejemplo.com/",
            "public.url-name": "  Ejemplo \n",
            "public.utf8-plain-text": "https://ejemplo.com/",
        ])

        let preview = await ItemPreviewBuilder.preview(of: [item], type: .link)

        #expect(preview == .link(LinkPreview(url: try #require(URL(string: "https://ejemplo.com/")), title: "Ejemplo")))
    }

    @Test func aLinkIsItsAddress() async throws {
        let preview = await ItemPreviewBuilder.preview(of: [.text("https://ejemplo.com/a?b=c")], type: .link)

        #expect(preview == .link(LinkPreview(url: try #require(URL(string: "https://ejemplo.com/a?b=c")))))
    }

    @Test func aLinkWithoutAnAddressHasNoPreview() async {
        #expect(await ItemPreviewBuilder.preview(of: [.text("no es una dirección")], type: .link) == .unknown)
    }

    @Test func aColourIsItsCode() async {
        #expect(await ItemPreviewBuilder.preview(of: [.text("#1A2B3C")], type: .color) == .color(ColorPreview(colorCode: 0x1A2B3C)))
        #expect(await ItemPreviewBuilder.preview(of: [.text("abcdef")], type: .color) == .color(ColorPreview(colorCode: 0xABCDEF)))
    }

    @Test func filesAreTheirPathsWithTheSizeAndPictureOfTheFirst() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = directory.appending(path: "a.txt")
        try Data(repeating: 65, count: 1234).write(to: first)

        let preview = await ItemPreviewBuilder.preview(of: [.file(first.path), .file("/tmp/b c.txt")], type: .files)

        guard case .files(let files) = preview else {
            Issue.record("Expected a files preview")
            return
        }
        #expect(files.paths == [first.path, "/tmp/b c.txt"])
        #expect(files.totalByteCount == 1234)
        #expect(files.thumbnailData != nil)
    }

    @Test func aFileThatCannotBeReadHasSizeZero() {
        #expect(FileSummary.byteCount(ofFileAt: "/nonexistent/\(UUID().uuidString)") == 0)
    }

    @Test func anImageIsPreviewedFromTheFirstItemThatHasOne() async throws {
        let png = TestImage.encoded(TestImage.solid(.red, width: 40, height: 30, hasAlpha: false))
        let items = [PasteboardItemSnapshot.text("caption"), PasteboardItemSnapshot(["public.png": png])]

        guard case .image(let preview) = await ItemPreviewBuilder.preview(of: items, type: .image) else {
            Issue.record("Expected an image preview")
            return
        }
        #expect(preview.width == 40)
        #expect(preview.height == 30)
        #expect(preview.thumbnailData != nil)
    }

    @Test func unknownContentHasNoPreview() async {
        #expect(await ItemPreviewBuilder.preview(of: [PasteboardItemSnapshot(strings: ["com.example.a": "1"])], type: .unknown) == .unknown)
    }

    @Test func contentIsClassifiedHashedAndPreviewedTogether() async throws {
        let timestamp = Date(timeIntervalSinceReferenceDate: 42)

        let item = try #require(await NewItem.captured(from: [.text("https://ejemplo.com")], at: timestamp))

        #expect(item.type == .link)
        #expect(item.checksum == "a0cde56d1ca04e4d003784f81f0cb0eb")
        #expect(item.preview == .link(LinkPreview(url: try #require(URL(string: "https://ejemplo.com")))))
        #expect(item.pasteboardItems == [.text("https://ejemplo.com")])
        #expect(item.timestamp == timestamp)
        #expect(item.sourceApplication == nil)
    }

    @Test func contentWithNothingToHashIsNotAnItem() async {
        #expect(await NewItem.captured(from: [], at: .now) == nil)
        #expect(await NewItem.captured(from: [.text("")], at: .now) == nil)
    }
}
