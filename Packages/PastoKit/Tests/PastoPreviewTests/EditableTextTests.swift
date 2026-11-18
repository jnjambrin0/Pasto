import AppKit
import PastoCore
import Testing
@testable import PastoPreview

@Suite struct EditableTextTests {
    private func attributes(of text: NSAttributedString, at index: Int = 0) -> [NSAttributedString.Key: Any] {
        text.attributes(at: index, effectiveRange: nil)
    }

    // MARK: Normalization

    @Test func keepsTheCharactersAndOneFontSize() {
        let text = NSAttributedString(string: "Hello", attributes: [
            .font: NSFont.systemFont(ofSize: 30),
            .foregroundColor: NSColor.red,
            .backgroundColor: NSColor.yellow,
            .link: "https://example.com",
            .paragraphStyle: NSParagraphStyle.default,
        ])
        let normalized = EditableText.normalized(text)
        #expect(normalized.string == "Hello")

        let kept = attributes(of: normalized)
        #expect(Set(kept.keys) == [.font])
        #expect((kept[.font] as? NSFont)?.pointSize == PreviewMetrics.editorFontSize)
        #expect(!EditableText.hasFormatting(normalized))
    }

    @Test func keepsBoldAndItalicButNotTheFamily() {
        let font = NSFontManager.shared.convert(NSFont(name: "Menlo", size: 18) ?? .systemFont(ofSize: 18), toHaveTrait: [.boldFontMask, .italicFontMask])
        let normalized = EditableText.normalized(NSAttributedString(string: "Hello", attributes: [.font: font]))

        let kept = attributes(of: normalized)
        #expect(TextTrait.bold.isActive(in: kept))
        #expect(TextTrait.italic.isActive(in: kept))
        #expect((kept[.font] as? NSFont)?.familyName == EditableText.baseFont.familyName)
        #expect(EditableText.hasFormatting(normalized))
    }

    @Test func keepsUnderlineAndStrikethroughWhereTheyWere() {
        let text = NSMutableAttributedString(string: "one two")
        text.addAttribute(.underlineStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 0, length: 3))
        text.addAttribute(.strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: NSRange(location: 4, length: 3))
        let normalized = EditableText.normalized(text)

        #expect(TextTrait.underline.isActive(in: attributes(of: normalized, at: 0)))
        #expect(!TextTrait.strikethrough.isActive(in: attributes(of: normalized, at: 0)))
        #expect(TextTrait.strikethrough.isActive(in: attributes(of: normalized, at: 5)))
        #expect(!TextTrait.underline.isActive(in: attributes(of: normalized, at: 5)))
    }

    /// The editor compares what it holds, normalized, with the normalized stored text: the two
    /// must agree when nothing changed, whatever colours the editor added for display.
    @Test func isStableAndIgnoresColours() {
        let text = NSMutableAttributedString(string: "Hello 👍🏽 world", attributes: [.font: NSFont.boldSystemFont(ofSize: 12)])
        let normalized = EditableText.normalized(text)
        #expect(EditableText.normalized(normalized).isEqual(to: normalized))

        let coloured = NSMutableAttributedString(attributedString: normalized)
        coloured.addAttribute(.foregroundColor, value: NSColor.white, range: NSRange(location: 0, length: coloured.length))
        #expect(EditableText.normalized(coloured).isEqual(to: normalized))
    }

    @Test func plainTextHasNoFormatting() {
        #expect(!EditableText.hasFormatting(NSAttributedString(string: "Hello")))
        #expect(!EditableText.hasFormatting(NSAttributedString()))
    }

    // MARK: Traits

    @Test func togglingAFontTraitKeepsFamilyAndSize() {
        var attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 17)]
        #expect(!TextTrait.bold.isActive(in: attributes))

        TextTrait.bold.set(true, in: &attributes)
        #expect(TextTrait.bold.isActive(in: attributes))
        #expect(!TextTrait.italic.isActive(in: attributes))
        #expect((attributes[.font] as? NSFont)?.pointSize == 17)

        TextTrait.italic.set(true, in: &attributes)
        TextTrait.bold.set(false, in: &attributes)
        #expect(!TextTrait.bold.isActive(in: attributes))
        #expect(TextTrait.italic.isActive(in: attributes))
    }

    @Test func togglingALineAddsAndRemovesItsAttribute() {
        var attributes: [NSAttributedString.Key: Any] = [:]
        TextTrait.underline.set(true, in: &attributes)
        #expect(TextTrait.underline.isActive(in: attributes))
        #expect(!TextTrait.strikethrough.isActive(in: attributes))

        TextTrait.underline.set(false, in: &attributes)
        #expect(attributes[.underlineStyle] == nil)
    }

    @Test func onlyASingleLineCountsAsUnderlined() {
        #expect(!TextTrait.underline.isActive(in: [.underlineStyle: NSUnderlineStyle.double.rawValue]))
    }

    // MARK: Stored text

    @Test func showsTheFormattedTextOfAnItemBeforeItsString() throws {
        let formatted = NSAttributedString(string: "Rich", attributes: [.font: NSFont.boldSystemFont(ofSize: 14)])
        let rtf = try #require(formatted.rtf(from: NSRange(location: 0, length: formatted.length), documentAttributes: [:]))
        let item = PasteboardItemSnapshot(
            types: ["public.rtf", "public.utf8-plain-text"],
            dataByType: ["public.rtf": rtf, "public.utf8-plain-text": Data("Plain".utf8)]
        )
        let text = ItemText.text(of: item)
        #expect(text.string == "Rich")
        #expect(TextTrait.bold.isActive(in: attributes(of: text)))
    }

    @Test func fallsBackToTheStringAndThenToNothing() {
        let plain = PasteboardItemSnapshot(
            types: ["public.utf8-plain-text"], dataByType: ["public.utf8-plain-text": Data("Plain".utf8)]
        )
        #expect(ItemText.text(of: plain).isEqual(to: NSAttributedString(string: "Plain")))
        #expect(ItemText.text(of: PasteboardItemSnapshot(types: [], dataByType: [:])).length == 0)
        #expect(ItemText.text(of: nil).length == 0)
    }
}
