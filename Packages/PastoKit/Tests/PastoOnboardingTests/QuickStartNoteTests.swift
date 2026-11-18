import AppKit
import Carbon.HIToolbox
@testable import PastoOnboarding
import PastoInput
import Testing

/// Quick Start says why the activation shortcut is not ⇧⌘V.
struct QuickStartNoteTests {
    private func note(for shortcut: Shortcut?) -> String? {
        QuickStartModel.note(for: shortcut) { ShortcutDisplay.string(for: $0, spaceKeyName: "Space") { _ in "V" } }
    }

    @Test func theFirstChoiceNeedsNoNote() {
        #expect(note(for: ShortcutDefaults.activation) == nil)
        #expect(note(for: Shortcut(keyCode: kVK_ANSI_P, modifiers: .control)) == nil)
    }

    @Test func theAlternateNamesTheShortcutAnotherAppHas() throws {
        let text = try #require(note(for: ShortcutDefaults.alternateActivation))

        #expect(text.contains("⇧⌘V"))
        #expect(!text.contains("⌃⇧⌘V"))
    }

    @Test func noShortcutNamesBothThatAreTaken() throws {
        let text = try #require(note(for: nil))

        #expect(text.contains("⇧⌘V"))
        #expect(text.contains("⌃⇧⌘V"))
    }
}
