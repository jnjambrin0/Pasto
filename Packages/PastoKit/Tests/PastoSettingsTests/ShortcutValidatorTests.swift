import AppKit
import Carbon.HIToolbox
import PastoInput
import Testing

/// Shortcuts that macOS or the key equivalents of Pasto's menus already use.
struct ShortcutValidatorTests {
    private let validator = ShortcutValidator(
        systemShortcuts: [
            // ⌘Space, as Spotlight has it.
            .init(keyCode: kVK_Space, carbonModifiers: cmdKey),
            // ⌃F2 with the function-key bit the system adds.
            .init(keyCode: kVK_F2, carbonModifiers: controlKey | 0x20000),
        ],
        menuKeyEquivalents: [
            .init(title: "Copy", key: "c", modifiers: .command),
            .init(title: "Redo", key: "Z", modifiers: .command),
            .init(title: "Paste and Match Style", key: "v", modifiers: [.command, .option, .shift]),
            .init(title: "Open", key: "\r", modifiers: .command),
        ]
    )

    @Test func aShortcutMacOSHasIsUsedBySystem() {
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_Space, modifiers: .command), key: " ") == .usedBySystem)
    }

    @Test func theSystemsModifiersMustMatchExactly() {
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_Space, modifiers: [.command, .shift]), key: " ") == nil)
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_F2, modifiers: .control), key: nil) == nil)
    }

    @Test func aMenuItemsKeyEquivalentIsUsedByItsItem() {
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_ANSI_C, modifiers: .command), key: "c") == .usedByMenuItem("Copy"))
        let pasteAndMatchStyle = Shortcut(keyCode: kVK_ANSI_V, modifiers: [.command, .option, .shift])
        #expect(validator.conflict(for: pasteAndMatchStyle, key: "v") == .usedByMenuItem("Paste and Match Style"))
    }

    @Test func anUppercaseKeyEquivalentStandsForShift() {
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_ANSI_Z, modifiers: [.command, .shift]), key: "z") == .usedByMenuItem("Redo"))
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_ANSI_Z, modifiers: .command), key: "z") == nil)
    }

    @Test func returnIsACarriageReturn() {
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_Return, modifiers: .command), key: "\r") == .usedByMenuItem("Open"))
    }

    @Test func otherModifiersOrKeysAreFree() {
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_ANSI_C, modifiers: [.command, .control]), key: "c") == nil)
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_ANSI_X, modifiers: .command), key: "x") == nil)
        #expect(validator.conflict(for: Shortcut(keyCode: kVK_F5, modifiers: []), key: nil) == nil)
    }

    @Test func theSystemIsLookedAtBeforeTheMenus() {
        let validator = ShortcutValidator(
            systemShortcuts: [.init(keyCode: kVK_ANSI_C, carbonModifiers: cmdKey)],
            menuKeyEquivalents: [.init(title: "Copy", key: "c", modifiers: .command)]
        )

        #expect(validator.conflict(for: Shortcut(keyCode: kVK_ANSI_C, modifiers: .command), key: "c") == .usedBySystem)
    }
}
