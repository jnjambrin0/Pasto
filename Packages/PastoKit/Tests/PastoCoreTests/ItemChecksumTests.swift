import CryptoKit
import Foundation
@testable import PastoCore
import Testing

/// The expected values are MD5 sums computed with `md5 -s`.
struct ItemChecksumTests {
    private func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    // MARK: - Text and colour

    @Test func textIsHashedAsItsUTF8Bytes() {
        #expect(ItemChecksum.checksum(of: [.text("hola")], type: .text) == "4d186321c1a7f0f354b297e8914ab240")
        #expect(ItemChecksum.checksum(of: [.text("#1A2B3C")], type: .color) == "3d53fc2532baf08f614a2ce3f6972a7e")
    }

    @Test func nothingIsNormalisedInText() {
        let plain = ItemChecksum.checksum(of: [.text("hola")], type: .text)

        #expect(ItemChecksum.checksum(of: [.text("hola ")], type: .text) != plain)
        #expect(ItemChecksum.checksum(of: [.text("Hola")], type: .text) != plain)
    }

    @Test func formattingDoesNotCount() {
        let formatted = PasteboardItemSnapshot(strings: [
            "public.rtf": "{\\rtf1\\ansi{\\b hola}}",
            "public.html": "<b>hola</b>",
            "public.utf8-plain-text": "hola",
        ])

        #expect(ItemChecksum.checksum(of: [formatted], type: .text) == "4d186321c1a7f0f354b297e8914ab240")
    }

    @Test func onlyTheFirstItemOfATextCounts() {
        #expect(ItemChecksum.checksum(of: [.text("hola"), .text("adiós")], type: .text) == "4d186321c1a7f0f354b297e8914ab240")
    }

    @Test func theStringComesFromTheFirstTextTypeThatIsValidUTF8() {
        let item = PasteboardItemSnapshot([
            "public.utf8-plain-text": Data("segundo".utf8),
            "public.plain-text": Data([0xFF, 0xFE, 0x00]),
            "public.text": Data("hola".utf8),
        ])

        // `public.plain-text` comes first but is not UTF-8; `public.utf8-plain-text` is next.
        #expect(item.plainText == "segundo")
        #expect(PasteboardItemSnapshot(strings: ["public.url": "https://ejemplo.com"]).plainText == "https://ejemplo.com")
        #expect(PasteboardItemSnapshot(strings: ["public.utf16-plain-text": "hola"]).plainText == nil)
    }

    @Test func anEmptyStringFallsBackToTheFormattedText() {
        let item = PasteboardItemSnapshot(strings: [
            "public.utf8-plain-text": "",
            "public.rtf": "{\\rtf1\\ansi texto con formato}",
        ])

        #expect(ItemChecksum.checksum(of: [item], type: .text) == "4bd30f5ecdae6748d53338a9d9590c60")
    }

    @Test func textWithNothingToHashHasNoChecksum() {
        #expect(ItemChecksum.checksum(of: [.text("")], type: .text) == nil)
        #expect(ItemChecksum.checksum(of: [PasteboardItemSnapshot(strings: ["public.rtf": "{\\rtf1 hola}"])], type: .text) == nil)
        #expect(ItemChecksum.checksum(of: [], type: .text) == nil)
    }

    // MARK: - Links

    @Test func aWebAddressHashesTheSameWithOrWithoutItsTrailingSlash() {
        let root = "a0cde56d1ca04e4d003784f81f0cb0eb" // https://ejemplo.com/
        #expect(ItemChecksum.checksum(of: [.text("https://ejemplo.com")], type: .link) == root)
        #expect(ItemChecksum.checksum(of: [.text("https://ejemplo.com/")], type: .link) == root)

        let page = "94febf919a4b05b23f6432cb54d3f03f" // https://ejemplo.com/a
        #expect(ItemChecksum.checksum(of: [.text("https://ejemplo.com/a/")], type: .link) == page)
        #expect(ItemChecksum.checksum(of: [.text("https://ejemplo.com/a")], type: .link) == page)

        // https://ejemplo.com/?q=1#f
        #expect(ItemChecksum.checksum(of: [.text("https://ejemplo.com?q=1#f")], type: .link) == "409c93c3d6f9d4e3746fc722b16a0bd5")
    }

    @Test func aWebAddressIsNotLowercased() {
        #expect(ItemChecksum.checksum(of: [.text("HTTPS://Ejemplo.com/a")], type: .link) == "d5942f1fcf892537de802d95a851e87b")
    }

    @Test func theSameStringHashesDifferentlyAsTextAndAsLink() {
        let item = PasteboardItemSnapshot.text("https://ejemplo.com")

        #expect(ItemChecksum.checksum(of: [item], type: .text) != ItemChecksum.checksum(of: [item], type: .link))
    }

    // MARK: - Files

    @Test func filesHashThePathsOfAllItemsRunTogether() {
        let items: [PasteboardItemSnapshot] = [.file("/tmp/a.txt"), .text("not a file"), .file("/tmp/b c.txt")]

        // FileSnippet:/tmp/a.txt/tmp/b c.txt
        #expect(ItemChecksum.checksum(of: items, type: .files) == "b3c65c1033414ff76048f27b17b9006a")
        #expect(ItemChecksum.checksum(of: [.text("not a file")], type: .files) == nil)
    }

    // MARK: - Images

    @Test func imagesHashTheImageDataOfEveryItemInOrder() {
        let first = Data([1, 2, 3])
        let second = Data([4, 5])
        let items = [
            // PNG is preferred to TIFF whatever the order they were declared in.
            PasteboardItemSnapshot(["public.tiff": Data([9, 9]), "public.png": first]),
            PasteboardItemSnapshot.text("caption"),
            PasteboardItemSnapshot(["public.jpeg": second]),
        ]

        #expect(ItemChecksum.checksum(of: items, type: .image) == md5(first + second))
        #expect(ItemChecksum.checksum(of: items.reversed(), type: .image) == md5(second + first))
        #expect(ItemChecksum.checksum(of: [.text("caption")], type: .image) == nil)
    }

    // MARK: - Unknown

    @Test func unknownContentHashesEverythingItHas() {
        let item = PasteboardItemSnapshot(strings: ["com.example.a": "1", "com.example.b": "2"])
        let checksum = ItemChecksum.checksum(of: [item], type: .unknown)

        #expect(checksum?.count == 32)
        #expect(checksum == ItemChecksum.checksum(of: [item], type: .unknown))
        #expect(checksum != ItemChecksum.checksum(of: [PasteboardItemSnapshot(strings: ["com.example.a": "1", "com.example.b": "3"])], type: .unknown))
        #expect(checksum != ItemChecksum.checksum(of: [PasteboardItemSnapshot(strings: ["com.example.b": "2", "com.example.a": "1"])], type: .unknown))
        #expect(ItemChecksum.checksum(of: [], type: .unknown) == nil)
    }
}
