import CryptoKit
import Foundation
@testable import PastoCore
import Testing

/// What capture does to spare large copies — one decoding of the string, hashing in place, a
/// quick look before trying a long text as an address — must not change a single checksum,
/// type or preview: the user's store holds items keyed by the checksums computed before.
struct LargeCaptureEquivalenceTests {
    private func md5(_ data: Data) -> String {
        Insecure.MD5.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    private static let strings = [
        "hola",
        "",
        "#1A2B3C",
        "ñandú, pingüino y 漢字 🇪🇸👩‍👩‍👧",
        "línea\r\notra\u{2028}y\u{0}nul",
        "https://ejemplo.com/a/",
        String(repeating: "texto largo con acentos áéíóú ", count: 40_000),
    ]

    /// The checksum as it was computed before: an MD5 of a copy of the string's UTF-8 bytes.
    @Test(arguments: strings)
    func textAndColourHashAsBefore(string: String) {
        let item = PasteboardItemSnapshot.text(string)
        let before = item.text.map { md5(Data($0.utf8)) }

        #expect(ItemChecksum.checksum(of: [item], type: .text) == before)
        #expect(ItemChecksum.checksum(of: [item], type: .color) == before)
        #expect(ItemChecksum.checksum(of: [item], type: .link) == item.text.map { md5(Data(LinkNormalizer.normalized($0).utf8)) })
    }

    @Test func aByteOrderMarkCountsAsBefore() {
        let item = PasteboardItemSnapshot(["public.utf8-plain-text": Data([0xEF, 0xBB, 0xBF]) + Data("hola".utf8)])
        let before = item.text.map { md5(Data($0.utf8)) }

        #expect(before != nil)
        #expect(ItemChecksum.checksum(of: [item], type: .text) == before)
    }

    @Test func filesHashAsBefore() {
        let items: [PasteboardItemSnapshot] = [.file("/tmp/ñandú.txt"), .file("/tmp/b c.txt")]
        let paths = items.compactMap(\.filePath)

        #expect(ItemChecksum.checksum(of: items, type: .files) == md5(Data(("FileSnippet:" + paths.joined()).utf8)))
    }

    /// Pinned values, computed with the archive as it was built before.
    @Test func unknownContentHashesAsBefore() {
        let small = PasteboardItemSnapshot(strings: ["com.example.a": "1", "com.example.b": "2"])
        #expect(ItemChecksum.checksum(of: [small], type: .unknown) == "1ee1aeea3dd13033eea7e8c2d966de74")

        var large = Data(count: 70_000)
        for index in large.indices { large[index] = UInt8(truncatingIfNeeded: index &* 31) }
        let items = [
            PasteboardItemSnapshot(["com.adobe.pdf": large, "public.utf16-plain-text": Data([0x68, 0, 0x69, 0])]),
            PasteboardItemSnapshot(["com.adobe.pdf": large]),
        ]
        #expect(ItemChecksum.checksum(of: items, type: .unknown) == "7caefa93c5a78f355151d0ce66cb1110")
    }

    /// Capturing gives what each step gives on its own.
    @Test(arguments: [
        [PasteboardItemSnapshot.text("hola")],
        [.text("#1A2B3C")],
        [.text("https://ejemplo.com/a/")],
        [PasteboardItemSnapshot(strings: ["public.url": "https://ejemplo.com", "public.utf8-plain-text": "Ejemplo"])],
        [PasteboardItemSnapshot(strings: ["public.utf8-plain-text": "", "public.rtf": "{\\rtf1\\ansi texto con formato}"])],
        [.text(String(repeating: "texto largo ", count: 50_000))],
        [PasteboardItemSnapshot(strings: ["com.example.a": "1"])],
    ])
    func captureMatchesItsSteps(items: [PasteboardItemSnapshot]) async throws {
        let type = ItemTypeDetector.type(of: items)
        let item = try #require(await NewItem.captured(from: items, at: Date(timeIntervalSinceReferenceDate: 0)))

        #expect(item.type == type)
        #expect(item.checksum == ItemChecksum.checksum(of: items, type: type))
        #expect(item.preview == (await ItemPreviewBuilder.preview(of: items, type: type)))
    }

    @Test func aLongStringIsNeverAColour() {
        #expect(HexColor.code(of: "#1A2B3C") == 0x1A2B3C)
        #expect(HexColor.code(of: "#1A2B3C" + String(repeating: " ", count: HexColor.maximumLength)) == nil)
        #expect(HexColor.code(of: String(repeating: "a", count: 1_000_000)) == nil)
    }
}

/// The text preview is measured and cut without asking the string for UTF-16 offsets, which
/// indexes the whole string first. It must measure and cut as before.
struct PreviewTextEquivalenceTests {
    /// The cut as it was made before: by UTF-16 offset, then back to a character boundary.
    private func truncatedBefore(_ text: String) -> String {
        guard text.utf16.count > ItemPreviewBuilder.textLimit else { return text }
        var end = text.utf16.index(text.utf16.startIndex, offsetBy: ItemPreviewBuilder.textLimit)
        while end.samePosition(in: text) == nil {
            end = text.utf16.index(before: end)
        }
        return String(text[..<end])
    }

    private static let pieces = ["a", " ", "ñ", "e\u{301}", "漢", "😀", "👩‍👩‍👧", "🇪🇸", "\r\n", "क्ष", "𝄞", "\u{0}"]

    @Test(arguments: Array(UInt64(1)...100))
    func textIsMeasuredAndCutAsBefore(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        let text = (0..<Int.random(in: 0...700, using: &random)).map { _ in Self.pieces.randomElement(using: &random)! }.joined()
        #expect(ItemPreviewBuilder.utf16Count(of: text) == text.utf16.count)
        #expect(ItemPreviewBuilder.truncated(text) == truncatedBefore(text))
    }

    @Test func aBridgedStringIsMeasuredToo() {
        let bridged = NSString(string: "texto 😀 con acentos ñ") as String
        #expect(ItemPreviewBuilder.utf16Count(of: bridged) == bridged.utf16.count)
    }
}

struct PasteboardWriteLimitTests {
    /// Measured on macOS 27.2: 255 MiB is written, 256 MiB makes the whole write fail.
    @Test func representationsUnder256MiBAreWritten() {
        #expect(GeneralPasteboardSource.isWritable(byteCount: 255 * 1_048_576))
        #expect(GeneralPasteboardSource.isWritable(byteCount: 256 * 1_048_576 - 1))
        #expect(!GeneralPasteboardSource.isWritable(byteCount: 256 * 1_048_576))
        #expect(!GeneralPasteboardSource.isWritable(byteCount: 900 * 1_048_576))
    }
}

struct TypedAddressTests {
    private static let urlCharacters = CharacterSet.urlQueryAllowed.union(.urlFragmentAllowed).union(CharacterSet(charactersIn: "#"))

    /// The address of a typed string as it was read before: percent-encoded and parsed, whatever its length.
    private func addressBefore(_ string: String) -> URL? {
        guard let url = string.addingPercentEncoding(withAllowedCharacters: Self.urlCharacters).flatMap({ URL(string: $0) }),
              url.scheme != nil, let host = url.host(), !host.isEmpty
        else { return nil }
        return url
    }

    private static let padding = String(repeating: " palabra", count: 400)

    @Test(arguments: [
        "https://ejemplo.com",
        "HTTPS://Ejemplo.com/a?b=c#d",
        "ftp://servidor/x",
        "miapp://host",
        "a+b-c.d://host/path",
        " https://ejemplo.com",
        "mira https://ejemplo.com",
        "https:ejemplo.com",
        "https:/ejemplo.com",
        "https:\\\\ejemplo.com",
        "mailto:alguien@ejemplo.com",
        "nota: compra pan",
        "//ejemplo.com/a",
        "#https://ejemplo.com",
        "1http://ejemplo.com",
        "ñ://ejemplo.com",
        "/tmp/fichero",
        "\u{FEFF}https://ejemplo.com",
    ])
    func aLongStringIsReadAsAnAddressAsBefore(start: String) {
        let long = start + Self.padding
        #expect(long.utf8.count > TypedAddress.quickRejectLength)

        // The item's string is what was tried before (decoding drops a byte-order mark).
        let item = PasteboardItemSnapshot.text(long)
        #expect(item.url == item.plainText.flatMap(addressBefore))
        // Short strings take the full test whatever they start with.
        let short = PasteboardItemSnapshot.text(start)
        #expect(short.url == short.plainText.flatMap(addressBefore))
    }

    @Test func onlyTheStartOfASchemeAndAnAuthorityLetsALongStringThrough() {
        #expect(TypedAddress.startsWithSchemeAndAuthority(Array("https://x".utf8)))
        #expect(TypedAddress.startsWithSchemeAndAuthority(Array("a1+.-://".utf8)))
        #expect(!TypedAddress.startsWithSchemeAndAuthority(Array("https:/x".utf8)))
        #expect(!TypedAddress.startsWithSchemeAndAuthority(Array("1a://x".utf8)))
        #expect(!TypedAddress.startsWithSchemeAndAuthority(Array("://x".utf8)))
        #expect(!TypedAddress.startsWithSchemeAndAuthority(Array("".utf8)))
        #expect(!TypedAddress.startsWithSchemeAndAuthority(Array("https".utf8)))
        #expect(TypedAddress.mayHaveSchemeAndHost("hola"))
        #expect(!TypedAddress.mayHaveSchemeAndHost("hola" + Self.padding))
    }
}
