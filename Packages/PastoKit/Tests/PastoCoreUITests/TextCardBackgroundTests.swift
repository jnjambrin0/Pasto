import AppKit
import Testing
@testable import PastoCoreUI

/// The fill of a text card, chosen from the colours of its text and the system mode.
@Suite struct TextCardBackgroundTests {
    static let darkDefault = CardBackground.color(ColorCode(rawValue: 0x1E1E1E))
    static let lightDefault = CardBackground.color(ColorCode(rawValue: 0xFFFFFF))

    func rich(_ pieces: [(String, [NSAttributedString.Key: Any])]) -> NSAttributedString {
        let text = NSMutableAttributedString()
        for (string, attributes) in pieces {
            var attributes = attributes
            attributes[.font] = NSFont.systemFont(ofSize: 14)
            text.append(NSAttributedString(string: string, attributes: attributes))
        }
        return text
    }

    func background(of text: NSAttributedString, isDark: Bool) -> CardBackground {
        TextCardBackground.resolve(TextCardBackground.summary(of: text), isDark: isDark)
    }

    @Test func textWithoutAnyAttributeIsPlain() {
        let text = NSAttributedString(string: "let x = 1")
        #expect(TextCardBackground.summary(of: text) == .plain)
        #expect(background(of: text, isDark: true) == .plainText)
        #expect(background(of: text, isDark: false) == .plainText)
    }

    @Test func emptyTextIsPlain() {
        #expect(TextCardBackground.summary(of: NSAttributedString()) == .plain)
    }

    /// Text with a font but no colour is drawn in the primary text colour, so its background
    /// follows the mode: dark gray in dark mode, white in light mode.
    @Test func richTextWithoutColorsFollowsTheMode() {
        let text = rich([("bold and italic", [:])])
        #expect(!TextCardBackground.summary(of: text).isPlain)
        #expect(background(of: text, isDark: true) == Self.darkDefault)
        #expect(background(of: text, isDark: false) == Self.lightDefault)
    }

    @Test func darkTextGetsAWhiteCardEvenInDarkMode() {
        let text = rich([("copied from a document", [.foregroundColor: NSColor.black])])
        #expect(background(of: text, isDark: true) == Self.lightDefault)
        #expect(background(of: text, isDark: false) == Self.lightDefault)
    }

    @Test func lightTextGetsADarkCardEvenInLightMode() {
        let text = rich([("copied from a terminal", [.foregroundColor: NSColor.white])])
        #expect(background(of: text, isDark: true) == Self.darkDefault)
        #expect(background(of: text, isDark: false) == Self.darkDefault)
    }

    @Test func dominantColorIsCountedByCharacters() {
        let orange = NSColor(srgbRed: 1, green: 0.584, blue: 0, alpha: 1)
        // Six orange characters among many uncoloured ones: the default text colour wins.
        let mostlyDefault = rich([("ProbeKit seed: rich text with ", [:]), ("orange", [.foregroundColor: orange]), (" words.", [:])])
        #expect(TextCardBackground.summary(of: mostlyDefault).dominantForeground == nil)

        let mostlyBlack = rich([("a long run of black text ", [.foregroundColor: NSColor.black]), ("white", [.foregroundColor: NSColor.white])])
        #expect(TextCardBackground.summary(of: mostlyBlack).dominantForeground == ColorCode(rawValue: 0xFF00_0000))
    }

    @Test func explicitColorWinsATie() {
        let text = rich([("abcd", [.foregroundColor: NSColor.black]), ("efgh", [:])])
        #expect(TextCardBackground.summary(of: text).dominantForeground == ColorCode(rawValue: 0xFF00_0000))
        // The first of two equally common explicit colours wins.
        let two = rich([("abcd", [.foregroundColor: NSColor.white]), ("efgh", [.foregroundColor: NSColor.black])])
        #expect(TextCardBackground.summary(of: two).dominantForeground == ColorCode(rawValue: 0xFFFF_FFFF))
    }

    @Test func textsOwnBackgroundIsUsedWhenItCoversMostOfIt() {
        let yellow = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 1)
        let highlighted = rich([("highlighted from start to end", [.backgroundColor: yellow])])
        #expect(background(of: highlighted, isDark: true) == .color(ColorCode(rawValue: 0xFFFF_FF00)))

        let partly = rich([("one", [.backgroundColor: yellow]), (" word highlighted in a longer text", [:])])
        #expect(background(of: partly, isDark: true) == Self.darkDefault)
    }

    @Test func translucentBackgroundFallsBackToTheDefault() {
        let wash = NSColor(srgbRed: 1, green: 1, blue: 0, alpha: 0.3)
        let text = rich([("highlighted with a translucent colour", [.backgroundColor: wash])])
        #expect(background(of: text, isDark: true) == .richTextFallback)
        #expect(background(of: text, isDark: false) == .richTextFallback)

        let clear = rich([("fully clear background", [.backgroundColor: NSColor.clear])])
        #expect(background(of: clear, isDark: true) == .richTextFallback)
    }

    /// The card's content is drawn as in light mode on a light fill and as in dark mode on a
    /// dark one; the standard background keeps the window's appearance.
    @Test func appearanceFollowsTheFill() {
        #expect(CardBackground.standard.isLight(inDarkMode: true) == nil)
        #expect(CardBackground.plainText.isLight(inDarkMode: true) == false)
        #expect(CardBackground.plainText.isLight(inDarkMode: false) == true)
        #expect(CardBackground.richTextFallback.isLight(inDarkMode: true) == false)
        #expect(CardBackground.richTextFallback.isLight(inDarkMode: false) == true)
        #expect(CardBackground.color(ColorCode(rawValue: 0x34C759)).isLight(inDarkMode: true) == true)
        #expect(CardBackground.color(ColorCode(rawValue: 0x102040)).isLight(inDarkMode: false) == false)
        #expect(Self.darkDefault.isLight(inDarkMode: false) == false)
    }
}
