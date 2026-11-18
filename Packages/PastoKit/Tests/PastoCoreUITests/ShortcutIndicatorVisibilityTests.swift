import AppKit
import Testing
@testable import PastoCoreUI

/// Which parts of a card's shortcut indicator show for each keyboard state, with the default
/// modifiers: ⇧ for plain text, ⌘ for quick paste.
@Suite struct ShortcutIndicatorVisibilityTests {
    func visibility(
        held: NSEvent.ModifierFlags,
        index: Int?,
        isEnabled: Bool = true,
        plainText: NSEvent.ModifierFlags = .shift,
        quickPaste: NSEvent.ModifierFlags = .command
    ) -> ShortcutIndicatorVisibility {
        ShortcutIndicatorVisibility(
            isEnabled: isEnabled, heldFlags: held, plainTextFlags: plainText, quickPasteFlags: quickPaste, quickPasteIndex: index
        )
    }

    @Test func nothingHeldShowsNothing() {
        #expect(!visibility(held: [], index: 1).isVisible)
        #expect(!visibility(held: .option, index: 1).isVisible)
    }

    @Test func commandShowsTheNumberOfTheFirstNineCards() {
        let numbered = visibility(held: .command, index: 3)
        #expect(numbered.showsNumber)
        #expect(!numbered.showsPlainTextGlyph)

        #expect(!visibility(held: .command, index: nil).isVisible)
    }

    @Test func shiftShowsTheGlyphOnEveryCard() {
        for index in [1, nil] as [Int?] {
            let glyph = visibility(held: .shift, index: index)
            #expect(glyph.showsPlainTextGlyph)
            #expect(!glyph.showsNumber)
        }
    }

    @Test func bothModifiersShowBoth() {
        let both = visibility(held: [.command, .shift], index: 9)
        #expect(both.showsPlainTextGlyph)
        #expect(both.showsNumber)

        let unnumbered = visibility(held: [.command, .shift], index: nil)
        #expect(unnumbered.showsPlainTextGlyph)
        #expect(!unnumbered.showsNumber)
    }

    @Test func extraModifiersDoNotHide() {
        #expect(visibility(held: [.command, .option], index: 2).showsNumber)
    }

    @Test func aStripWithoutFocusShowsNothing() {
        #expect(!visibility(held: [.command, .shift], index: 1, isEnabled: false).isVisible)
    }

    @Test func customModifiers() {
        let settings = visibility(held: [.control, .option], index: 1, plainText: .option, quickPaste: [.control, .option])
        #expect(settings.showsPlainTextGlyph)
        #expect(settings.showsNumber)
        #expect(!visibility(held: .control, index: 1, plainText: .option, quickPaste: [.control, .option]).isVisible)
    }

    /// With no plain-text modifier configured, the condition always holds.
    @Test func anEmptyPlainTextModifierAlwaysShowsTheGlyph() {
        #expect(visibility(held: [], index: nil, plainText: []).showsPlainTextGlyph)
    }
}
