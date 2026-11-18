import Foundation
@testable import PastoCore
import Testing

/// The indexer reads only the start of an item's text (`IndexableText`). What it reads must
/// be the start of what decoding the whole text gives: the same representation chosen, the same
/// characters, however the text ends and wherever a character spans the cut.
struct IndexableTextPrefixTests {
    /// Pieces that make characters of several scalars and boundaries that depend on what is
    /// around them.
    private static let pieces = [
        "a", "Z", " ", "ñ", "é", "e\u{301}", "\u{301}", "漢", "🇪", "🇸", "👩‍👩‍👧", "👍🏽", "\r", "\n", "\r\n",
        "क्ष", "ि", "각", "\u{1100}", "\u{1161}", "\u{11A8}", "\u{200D}", "\u{FEFF}", "\u{0}", "ـ",
    ]

    private static func randomText(characters: Int, using random: inout SeededRandom) -> String {
        (0..<characters).map { _ in pieces.randomElement(using: &random)! }.joined()
    }

    /// The text as it was read before: every element's string decoded whole, joined.
    private func wholeText(of items: [PasteboardItemSnapshot]) -> String {
        items.compactMap(\.plainText).joined(separator: " ")
    }

    @Test(arguments: Array(UInt64(1)...200))
    func theStartIsTheStartOfTheWholeText(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        let limit = Int.random(in: 1...60, using: &random)
        let items = (0..<Int.random(in: 1...4, using: &random)).map { _ -> PasteboardItemSnapshot in
            var data = Data(Self.randomText(characters: Int.random(in: 0...(limit * 2), using: &random), using: &random).utf8)
            switch Int.random(in: 0..<8, using: &random) {
            case 0: data = Data([0xEF, 0xBB, 0xBF]) + data
            case 1: data = Data([0xEF, 0xBB, 0xBF, 0xEF, 0xBB, 0xBF]) + data
            case 2: data.append(0xFF)
            case 3: data.append(contentsOf: [0xE2, 0x82])
            default: break
            }
            // Sometimes the string is the second representation, the first not being UTF-8.
            if Int.random(in: 0..<4, using: &random) == 0 {
                return PasteboardItemSnapshot(["public.plain-text": Data([0xC0, 0x80]), "public.utf8-plain-text": data])
            }
            return PasteboardItemSnapshot(["public.utf8-plain-text": data])
        }

        let whole = wholeText(of: items)
        let expected = whole.isEmpty ? nil : String(whole.prefix(limit))
        #expect(IndexableText.text(of: items, preview: .unknown, type: .text, characters: limit) == expected)
        #expect(IndexableText.text(of: items, preview: .unknown, type: .unknown, characters: limit) == expected)
    }

    @Test func aHugeTextIsReadOnlyAsFarAsTheIndexKeeps() {
        let text = String(repeating: "texto largo con acentos áéíóú y 漢字 👩‍👩‍👧 ", count: 40_000)
        let items: [PasteboardItemSnapshot] = [.text(text), .text("second")]
        let expected = String(text.prefix(IndexableItem.maxTextLength))
        #expect(IndexableText.text(of: items, preview: .unknown, type: .text) == expected)

        let prefix = items[0].plainTextPrefix(characters: 10)
        #expect(prefix?.isWhole == false)
        #expect(prefix.map { $0.text.utf8.count < 1_000 } == true)
    }

    @Test(arguments: Array(UInt64(1)...40))
    func validUTF8IsWhatTheDecoderAccepts(seed: UInt64) {
        var random = SeededRandom(seed: seed)
        for _ in 0..<200 {
            let bytes = (0..<Int.random(in: 0...12, using: &random)).map { _ in
                [UInt8.random(in: 0...0x7F, using: &random), UInt8.random(in: 0x80...0xBF, using: &random),
                 UInt8.random(in: 0xC0...0xFF, using: &random), 0xED, 0xF4, 0xE0, 0xEF, 0xBB, 0xBF][Int.random(in: 0..<9, using: &random)]
            }
            let data = Data(bytes)
            #expect(PasteboardItemSnapshot.isValidUTF8(data) == (String(data: data, encoding: .utf8) != nil), "\(bytes)")
        }
    }
}
