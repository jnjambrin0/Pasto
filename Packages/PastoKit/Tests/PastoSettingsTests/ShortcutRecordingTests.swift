import AppKit
import Carbon.HIToolbox
import PastoInput
import Testing

/// What each key press does while a shortcut is being recorded.
struct ShortcutRecordingTests {
    private let paste = Shortcut(keyCode: kVK_ANSI_V, modifiers: [.command, .shift])

    private func outcome(
        _ keyCode: Int,
        _ modifiers: NSEvent.ModifierFlags,
        otherShortcuts: [NamedShortcut] = [],
        conflict: ShortcutConflict? = nil
    ) -> ShortcutRecording {
        ShortcutRecording.outcome(keyCode: keyCode, modifiers: modifiers, otherShortcuts: otherShortcuts) { _ in conflict }
    }

    @Test func aKeyWithCommandControlOrOptionBecomesTheShortcut() {
        #expect(outcome(kVK_ANSI_V, [.command, .shift]) == .record(paste))
        #expect(outcome(kVK_ANSI_P, .control) == .record(Shortcut(keyCode: kVK_ANSI_P, modifiers: .control)))
        #expect(outcome(kVK_ANSI_P, .option) == .record(Shortcut(keyCode: kVK_ANSI_P, modifiers: .option)))
    }

    @Test func modifiersThatAreNotPartOfShortcutsAreDropped() {
        #expect(outcome(kVK_RightArrow, [.command, .numericPad, .function, .capsLock]) == .record(Shortcut(keyCode: kVK_RightArrow, modifiers: .command)))
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .shift, .capsLock, .function, [.shift, .capsLock]])
    func aKeyWithoutCommandControlOrOptionIsRejected(modifiers: NSEvent.ModifierFlags) {
        #expect(outcome(kVK_ANSI_V, modifiers) == .reject)
    }

    @Test(arguments: [kVK_F1, kVK_F12, kVK_F19, kVK_F20])
    func aFunctionKeyIsAShortcutOnItsOwn(keyCode: Int) {
        #expect(outcome(keyCode, []) == .record(Shortcut(keyCode: keyCode, modifiers: [])))
        #expect(outcome(keyCode, .shift) == .record(Shortcut(keyCode: keyCode, modifiers: .shift)))
    }

    @Test func escapeCancelsAndDeleteClears() {
        #expect(outcome(kVK_Escape, []) == .cancel)
        #expect(outcome(kVK_Delete, []) == .clear)
        #expect(outcome(kVK_ForwardDelete, .function) == .clear)
    }

    @Test func withAModifierEscapeAndDeleteAreOrdinaryKeys() {
        #expect(outcome(kVK_Delete, .command) == .record(Shortcut(keyCode: kVK_Delete, modifiers: .command)))
        #expect(outcome(kVK_Escape, .shift) == .reject)
    }

    @Test func commandWAndCommandQKeepClosingAndQuitting() {
        #expect(outcome(kVK_ANSI_W, .command) == .cancelAndPassOn)
        #expect(outcome(kVK_ANSI_Q, .command) == .cancelAndPassOn)
        #expect(outcome(kVK_ANSI_W, [.command, .shift]) == .record(Shortcut(keyCode: kVK_ANSI_W, modifiers: [.command, .shift])))
    }

    @Test(arguments: [NSEvent.ModifierFlags(), .shift, .capsLock])
    func tabAndShiftTabEndTheRecordingAndMoveTheFocus(modifiers: NSEvent.ModifierFlags) {
        #expect(outcome(kVK_Tab, modifiers) == .cancelAndPassOn)
    }

    @Test func tabWithCommandControlOrOptionIsAShortcut() {
        #expect(outcome(kVK_Tab, .control) == .record(Shortcut(keyCode: kVK_Tab, modifiers: .control)))
        #expect(outcome(kVK_Tab, [.option, .shift]) == .record(Shortcut(keyCode: kVK_Tab, modifiers: [.option, .shift])))
    }

    @Test func aShortcutPastoAlreadyHasIsAConflictNamingIt() {
        let others = [
            NamedShortcut(name: "Show next pinboard", shortcut: Shortcut(keyCode: kVK_RightArrow, modifiers: .command)),
            NamedShortcut(name: "Open Paste Stack", shortcut: paste),
        ]

        #expect(outcome(kVK_ANSI_V, [.shift, .command], otherShortcuts: others) == .conflict(.usedByShortcut("Open Paste Stack")))
    }

    @Test func thePasteStacksPasteAllIsTaken() {
        let others = [NamedShortcut.pasteStackPasteAll(name: "Paste All")]

        #expect(outcome(kVK_ANSI_V, [.control, .option, .command], otherShortcuts: others) == .conflict(.usedByShortcut("Paste All")))
    }

    @Test func whatTheValidatorFindsIsAConflict() {
        #expect(outcome(kVK_Space, .command, conflict: .usedBySystem) == .conflict(.usedBySystem))
    }

    @Test func pastosOwnShortcutsAreLookedAtBeforeTheValidator() {
        let others = [NamedShortcut(name: "Open Paste Stack", shortcut: paste)]

        #expect(outcome(kVK_ANSI_V, [.shift, .command], otherShortcuts: others, conflict: .usedBySystem) == .conflict(.usedByShortcut("Open Paste Stack")))
    }

    @Test func aRejectedKeyIsNotValidated() {
        var validated = false
        _ = ShortcutRecording.outcome(keyCode: kVK_ANSI_V, modifiers: .shift, otherShortcuts: []) { _ in
            validated = true
            return nil
        }

        #expect(!validated)
    }
}
