import AppKit
import Foundation
@testable import PastoCore
import Testing

/// What is written on the pasteboard for the items being restored. The processor is a
/// pass-through here: what it does to images has its own tests.
struct PasteboardItemComposerTests {
    private func compose(_ items: [RestorableItem], options: RestoreOptions = []) -> [PasteboardItemSnapshot] {
        PasteboardItemComposer(includesSingleImageFile: false).compose(items, options: options) { _ in
            PassThroughProcessor()
        }
    }

    private let richHello = PasteboardItemSnapshot([
        "public.rtf": RichText.rtf("Hello", fontName: "Helvetica-Bold"),
        "public.utf8-plain-text": Data("Hello".utf8),
    ])
    private let image = PasteboardItemSnapshot(["public.png": Data([1, 2, 3])])

    // MARK: - String of an element and plain-text form

    @Test func theStringOfAnElementComesFromTheFirstTypeInPasteboardOrder() {
        let order = ["public.plain-text", "public.utf8-plain-text", "public.text", "public.url"]
        // Declared backwards: the order that counts is the fixed one, not the element's.
        var element = PasteboardItemSnapshot(
            types: order.reversed(),
            dataByType: Dictionary(uniqueKeysWithValues: order.map { ($0, Data($0.utf8)) })
        )

        // Each type holds its own name; taking the winner away lets the next one show.
        for type in order {
            #expect(element.restorableString == type)
            element.removeTypes { $0 == type }
        }
        #expect(element.restorableString == nil)
    }

    @Test func aTypeThatIsNotUTF8IsSkipped() {
        let element = PasteboardItemSnapshot([
            "public.plain-text": Data([0xFF, 0xFE, 0x00]),
            "public.url": Data("https://example.com".utf8),
        ])
        let utf16Only = PasteboardItemSnapshot(["public.utf16-plain-text": "hello".data(using: .utf16)!])

        #expect(element.restorableString == "https://example.com")
        #expect(utf16Only.restorableString == nil)
    }

    @Test func thePlainTextFormKeepsOnlyTheStringAsUTF8() {
        let link = PasteboardItemSnapshot([
            "public.html": Data("<a href='https://example.com'>café</a>".utf8),
            "public.url": Data("https://example.com/café".utf8),
        ])

        #expect(link.plainTextForm == .plainText("https://example.com/café"))
        #expect(image.plainTextForm == nil)
    }

    // MARK: - Which bit applies to which item

    @Test(arguments: [ItemType.text, .link])
    func textAndLinksBecomePlainOnlyWithTheTextBit(type: ItemType) {
        let item = RestorableItem.make(type, [richHello])

        #expect(compose([item]) == [richHello.signed()])
        #expect(compose([item], options: .nonTextAsPlainText) == [richHello.signed()])
        #expect(compose([item], options: .textAsPlainText) == [PasteboardItemSnapshot.plainText("Hello").signed()])
        #expect(compose([item], options: .plainText) == [PasteboardItemSnapshot.plainText("Hello").signed()])
    }

    @Test(arguments: [ItemType.files, .image, .color, .unknown])
    func otherItemsBecomePlainOnlyWithTheNonTextBit(type: ItemType) {
        let file = PasteboardItemSnapshot([
            "public.file-url": Data("file:///tmp/report.pdf".utf8),
            "public.utf8-plain-text": Data("report.pdf".utf8),
        ])
        let item = RestorableItem.make(type, [file])

        #expect(compose([item]) == [file.signed()])
        #expect(compose([item], options: .textAsPlainText) == [file.signed()])
        #expect(compose([item], options: .nonTextAsPlainText) == [PasteboardItemSnapshot.plainText("report.pdf").signed()])
        #expect(compose([item], options: .plainText) == [PasteboardItemSnapshot.plainText("report.pdf").signed()])
    }

    @Test func anElementWithoutTextDisappearsFromThePlainTextForm() {
        let item = RestorableItem.make(.image, [image, .plainText("caption")])

        #expect(compose([item], options: .plainText) == [PasteboardItemSnapshot.plainText("caption").signed()])
        #expect(compose([.make(.image, [image])], options: .plainText).isEmpty)
    }

    // MARK: - Sanitising

    @Test func bannedTypesAreRemovedBySubstringAndTheElementIsSigned() {
        let stored = PasteboardItemSnapshot([
            "public.rtf": Data("rtf".utf8),
            "com.microsoft.ole.source": Data("ole".utf8),
            "dyn.prefix.com.microsoft.ole.source.suffix": Data("ole too".utf8),
            "com.microsoft.Link-Source": Data("not banned".utf8),
            "public.utf8-plain-text": Data("text".utf8),
        ])

        let composed = compose([.make(.text, [stored], from: .safari)])

        #expect(composed == [
            PasteboardItemSnapshot(
                types: ["public.rtf", "com.microsoft.Link-Source", "public.utf8-plain-text", "org.nspasteboard.source", "jnjambrino.Pasto"],
                dataByType: [
                    "public.rtf": Data("rtf".utf8),
                    "com.microsoft.Link-Source": Data("not banned".utf8),
                    "public.utf8-plain-text": Data("text".utf8),
                    "org.nspasteboard.source": Data("com.apple.Safari".utf8),
                    "jnjambrino.Pasto": Data(),
                ]
            ),
        ])
    }

    @Test func anItemWithoutSourceApplicationGetsAnEmptySourceMarker() throws {
        let composed = compose([.make(.text, [.plainText("a")])])

        let element = try #require(composed.first)
        #expect(element.types.suffix(2) == ["org.nspasteboard.source", "jnjambrino.Pasto"])
        #expect(element.dataByType["org.nspasteboard.source"] == Data())
    }

    @Test func markersTheStoredItemAlreadyCarriesAreReplacedNotDuplicated() {
        let stored = PasteboardItemSnapshot([
            "jnjambrino.Pasto": Data([1]),
            "org.nspasteboard.source": Data("com.other.clipboard".utf8),
            "public.utf8-plain-text": Data("a".utf8),
        ])

        let composed = compose([.make(.text, [stored], from: .safari)])

        #expect(composed == [PasteboardItemSnapshot.plainText("a").signed(from: "com.apple.Safari")])
    }

    // MARK: - One item

    @Test func aSingleItemKeepsEveryOneOfItsElements() {
        let item = RestorableItem.make(.text, [richHello, .plainText("second")], from: .safari)

        #expect(compose([item]) == [
            richHello.signed(from: "com.apple.Safari"),
            PasteboardItemSnapshot.plainText("second").signed(from: "com.apple.Safari"),
        ])
    }

    // MARK: - The processor

    @Test func severalItemsMakeEveryImageGetAFile() {
        func flagGiven(to items: [RestorableItem], includesSingleImageFile: Bool) -> Bool? {
            var flag: Bool?
            _ = PasteboardItemComposer(includesSingleImageFile: includesSingleImageFile).compose(items, options: []) {
                flag = $0
                return PassThroughProcessor()
            }
            return flag
        }
        let one = [RestorableItem.make(.image, [image])]

        #expect(flagGiven(to: one, includesSingleImageFile: false) == false)
        #expect(flagGiven(to: one, includesSingleImageFile: true) == true)
        #expect(flagGiven(to: one + one, includesSingleImageFile: false) == true)
    }

    // MARK: - Several items

    @Test func severalItemsWithoutTextKeepEveryElementInOrder() {
        let file = PasteboardItemSnapshot(["public.file-url": Data("file:///tmp/a.pdf".utf8)])
        let color = PasteboardItemSnapshot.plainText("#FF0000")

        let composed = compose([
            .make(.image, [image, image], from: .safari),
            .make(.files, [file]),
            .make(.color, [color]),
        ])

        #expect(composed == [
            image.signed(from: "com.apple.Safari"),
            image.signed(from: "com.apple.Safari"),
            file.signed(),
            color.signed(),
        ])
    }

    @Test func severalItemsWithSomeTextBecomeOneRichTextElement() throws {
        let composed = compose([
            .make(.text, [richHello], from: .safari),
            .make(.image, [image]),
            .make(.link, [.plainText("https://example.com/ñ")]),
        ])

        // RTF and the same text as UTF-16 and UTF-8, signed as Pasto's write but without a
        // source; the image is gone.
        let element = try #require(composed.first)
        #expect(composed.count == 1)
        #expect(element.types == [
            "public.rtf", "public.utf16-external-plain-text", "public.utf8-plain-text", "jnjambrino.Pasto",
        ])
        #expect(element.dataByType["jnjambrino.Pasto"] == Data())
        #expect(element.dataByType.count == 4)

        let text = try #require(RichText.read(element.dataByType["public.rtf"]))
        #expect(text.string == "Hello\nhttps://example.com/ñ")
        #expect(RichText.isBold(text, at: 0))
        #expect(!RichText.isBold(text, at: 6))
        #expect(element.dataByType["public.utf8-plain-text"] == Data("Hello\nhttps://example.com/ñ".utf8))
        let utf16 = try #require(element.dataByType["public.utf16-external-plain-text"])
        #expect(String(data: utf16, encoding: .utf16) == "Hello\nhttps://example.com/ñ")
    }

    @Test func theUTF16TextStartsWithAByteOrderMark() {
        // "a", "ñ" and a character outside the basic plane, as a surrogate pair.
        #expect(MergedTextElement.externalUTF16("a\u{F1}\u{1F600}") == Data([
            0xFF, 0xFE, 0x61, 0x00, 0xF1, 0x00, 0x3D, 0xD8, 0x00, 0xDE,
        ]))
    }

    // MARK: - Several items, item by item (a drag)

    @Test func byItemTheMergedElementBelongsToTheFirstItemAndTheOthersCarryNothing() {
        let items: [RestorableItem] = [
            .make(.text, [.plainText("one")]),
            .make(.image, [image]),
            .make(.text, [.plainText("two")]),
        ]
        let byItem = PasteboardItemComposer(includesSingleImageFile: true).composeByItem(items, options: .plainText) { _ in
            PassThroughProcessor()
        }

        #expect(byItem == [
            [PasteboardItemSnapshot(["public.utf8-plain-text": Data("one\ntwo".utf8), "jnjambrino.Pasto": Data()])],
            [],
            [],
        ])
    }

    @Test func byItemSeveralItemsWithoutTextKeepTheirOwnElements() {
        let file = PasteboardItemSnapshot(["public.file-url": Data("file:///tmp/a.pdf".utf8)])

        let byItem = PasteboardItemComposer(includesSingleImageFile: true).composeByItem(
            [.make(.image, [image]), .make(.files, [file, file])],
            options: []
        ) { _ in PassThroughProcessor() }

        #expect(byItem == [[image.signed()], [file.signed(), file.signed()]])
    }

    @Test func byItemSeveralItemsWithNoTextToMergeCarryNothing() {
        let html = PasteboardItemSnapshot(["public.html": Data("<b>x</b>".utf8)])

        let byItem = PasteboardItemComposer(includesSingleImageFile: true).composeByItem(
            [.make(.text, [html]), .make(.image, [image])],
            options: []
        ) { _ in PassThroughProcessor() }

        #expect(byItem == [[], []])
    }

    @Test(arguments: [RestoreOptions.textAsPlainText, .plainText])
    func withTheTextBitTheMergedElementIsPlainText(options: RestoreOptions) {
        let composed = compose(
            [
                .make(.text, [richHello], from: .safari),
                .make(.image, [image]),
                .make(.link, [.plainText("https://example.com/ñ")]),
            ],
            options: options
        )

        #expect(composed == [
            PasteboardItemSnapshot([
                "public.utf8-plain-text": Data("Hello\nhttps://example.com/ñ".utf8),
                "jnjambrino.Pasto": Data(),
            ]),
        ])
    }

    @Test func theMergedTextFollowsTheOrderOfTheItemsAndOfTheirElements() {
        let composed = compose(
            [
                .make(.text, [.plainText("b1"), .plainText("b2")]),
                .make(.files, [.plainText("f")]),
                .make(.text, [.plainText("a")]),
            ],
            options: .textAsPlainText
        )

        #expect(composed.first?.dataByType["public.utf8-plain-text"] == Data("b1\nb2\nf\na".utf8))
    }

    @Test func richTextIsReadFromRTFDBeforeRTF() throws {
        let both = PasteboardItemSnapshot([
            "public.rtf": RichText.rtf("from rtf"),
            "com.apple.flat-rtfd": RichText.flatRTFD("from rtfd"),
        ])

        let composed = compose([.make(.text, [both]), .make(.text, [.plainText("x")])])

        let text = try #require(RichText.read(composed.first?.dataByType["public.rtf"]))
        #expect(text.string == "from rtfd\nx")
    }

    @Test func tablesAreFlattenedIntoParagraphs() throws {
        let table = RichText.rtfTable(cells: ["left", "right"])
        let source = try #require(RichText.read(table))
        // The fixture is only worth something if AppKit reads the table back as text blocks.
        try #require(RichText.textBlockCount(source) > 0)

        let composed = compose([.make(.text, [PasteboardItemSnapshot(["public.rtf": table])]), .make(.text, [.plainText("after")])])

        let text = try #require(RichText.read(composed.first?.dataByType["public.rtf"]))
        #expect(RichText.textBlockCount(text) == 0)
        #expect(source.string.contains("left") && source.string.contains("right"))
        #expect(text.string == source.string + "\nafter")
    }

    @Test func itemsWithNoTextAtAllWriteNothing() {
        let html = PasteboardItemSnapshot(["public.html": Data("<b>x</b>".utf8)])

        #expect(compose([.make(.text, [html]), .make(.image, [image])]).isEmpty)
    }
}

/// Rich text fixtures, built with AppKit so that no document lives in the repository.
private enum RichText {
    static func attributed(_ string: String, fontName: String = "Helvetica") -> NSAttributedString {
        NSAttributedString(string: string, attributes: [.font: NSFont(name: fontName, size: 12)!])
    }

    static func rtf(_ string: String, fontName: String = "Helvetica") -> Data {
        rtf(attributed(string, fontName: fontName))
    }

    static func rtf(_ text: NSAttributedString) -> Data {
        text.rtf(from: NSRange(location: 0, length: text.length), documentAttributes: [:])!
    }

    static func flatRTFD(_ string: String) -> Data {
        let text = attributed(string)
        return text.rtfd(from: NSRange(location: 0, length: text.length), documentAttributes: [:])!
    }

    /// A one-row table with a cell per string.
    static func rtfTable(cells: [String]) -> Data {
        let table = NSTextTable()
        table.numberOfColumns = cells.count
        let text = NSMutableAttributedString()
        for (column, cell) in cells.enumerated() {
            let style = NSMutableParagraphStyle()
            style.textBlocks = [NSTextTableBlock(table: table, startingRow: 0, rowSpan: 1, startingColumn: column, columnSpan: 1)]
            text.append(NSAttributedString(string: "\(cell)\n", attributes: [.paragraphStyle: style]))
        }
        return rtf(text)
    }

    static func read(_ rtf: Data?) -> NSAttributedString? {
        rtf.flatMap { NSAttributedString(rtf: $0, documentAttributes: nil) }
    }

    static func isBold(_ text: NSAttributedString, at index: Int) -> Bool {
        let font = text.attribute(.font, at: index, effectiveRange: nil) as? NSFont
        return font?.fontDescriptor.symbolicTraits.contains(.bold) ?? false
    }

    static func textBlockCount(_ text: NSAttributedString) -> Int {
        var count = 0
        text.enumerateAttribute(.paragraphStyle, in: NSRange(location: 0, length: text.length)) { value, _, _ in
            count += (value as? NSParagraphStyle)?.textBlocks.count ?? 0
        }
        return count
    }
}
