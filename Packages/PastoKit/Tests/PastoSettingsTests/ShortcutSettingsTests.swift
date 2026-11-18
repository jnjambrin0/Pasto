import AppKit
import Carbon.HIToolbox
import Foundation
import PastoFoundation
import PastoInput
import Testing

/// How shortcuts are stored, the initial shortcuts and restoring the defaults.
struct ShortcutSettingsTests {
    private let ephemeral = EphemeralDefaults()
    private var defaults: UserDefaults { ephemeral.defaults }
    private var config: ConfigStore { ConfigStore(defaults: defaults) }

    @Test func aShortcutIsStoredAsJSONWithItsKeyCodeAndCocoaModifiers() throws {
        config.setShortcut(Shortcut(keyCode: kVK_ANSI_V, modifiers: [.command, .shift]), for: .activationShortcut)

        let data = try #require(defaults.data(forKey: "activationShortcut"))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Int])
        #expect(json == ["keyCode": 9, "internalModifiers": 0x120000])
    }

    @Test func aShortcutWrittenInTheDocumentedFormatIsRead() {
        defaults.set(Data(#"{"keyCode":8,"internalModifiers":1179648}"#.utf8), forKey: "pasteStackShortcut")

        #expect(config.shortcut(for: .pasteStackShortcut) == ShortcutDefaults.pasteStack)
    }

    @Test(arguments: [
        #"{"keyCode":4294967296,"internalModifiers":1179648}"#,
        #"{"keyCode":-1,"internalModifiers":1179648}"#,
        #"{"keyCode":65536,"internalModifiers":0}"#,
    ])
    func aStoredShortcutWithAKeyCodeNoKeyHasReadsAsNone(json: String) {
        defaults.set(Data(json.utf8), forKey: "activationShortcut")

        #expect(config.shortcut(for: .activationShortcut) == nil)
    }

    @Test(arguments: [Data("not a shortcut".utf8), Data(#"{"keyCode":9}"#.utf8), Data()])
    func aStoredShortcutThatCannotBeDecodedReadsAsNone(data: Data) {
        defaults.set(data, forKey: "pasteStackShortcut")

        #expect(config.shortcut(for: .pasteStackShortcut) == nil)
    }

    @Test func aStoredShortcutOfAnotherTypeReadsAsNone() {
        defaults.set("⇧⌘V", forKey: "activationShortcut")

        #expect(config.shortcut(for: .activationShortcut) == nil)
    }

    @Test func theHighestKeyCodeIsStillAShortcut() {
        defaults.set(Data(#"{"keyCode":65535,"internalModifiers":1048576}"#.utf8), forKey: "activationShortcut")

        #expect(config.shortcut(for: .activationShortcut) == Shortcut(keyCode: 65_535, modifiers: .command))
    }

    @Test func clearingAShortcutForgetsTheKey() {
        config.setShortcut(ShortcutDefaults.activation, for: .activationShortcut)

        config.setShortcut(nil, for: .activationShortcut)

        #expect(defaults.object(forKey: "activationShortcut") == nil)
        #expect(config.shortcut(for: .activationShortcut) == nil)
    }

    @Test func theInitialShortcutsAreAppliedOnceAndOnlyWhereNothingIsSet() {
        let custom = Shortcut(keyCode: kVK_ANSI_P, modifiers: .control)
        config.setShortcut(custom, for: .pasteStackShortcut)

        ShortcutDefaults.applyInitialShortcuts(to: config) { _ in true }

        #expect(config.shortcut(for: .activationShortcut) == Shortcut(keyCode: 9, modifiers: [.command, .shift]))
        #expect(config.shortcut(for: .pasteStackShortcut) == custom)
        #expect(config.shortcut(for: .nextPinboardShortcut) == Shortcut(keyCode: 124, modifiers: .command))
        #expect(config.shortcut(for: .previousPinboardShortcut) == Shortcut(keyCode: 123, modifiers: .command))
        #expect(config.value(for: .isInitialShortcutsMigrationCompleted))

        config.setShortcut(nil, for: .activationShortcut)
        ShortcutDefaults.applyInitialShortcuts(to: config) { _ in true }

        #expect(config.shortcut(for: .activationShortcut) == nil)
    }

    @Test func aStoredShortcutThatCannotBeReadGetsItsInitialValue() {
        defaults.set(Data("not a shortcut".utf8), forKey: "activationShortcut")

        ShortcutDefaults.applyInitialShortcuts(to: config) { _ in true }

        #expect(config.shortcut(for: .activationShortcut) == ShortcutDefaults.activation)
    }

    // MARK: Initial shortcuts that something else has

    @Test func aTakenFirstChoiceGivesWayToTheAlternate() {
        let taken: Set<Shortcut> = [ShortcutDefaults.activation, ShortcutDefaults.pasteStack]

        ShortcutDefaults.applyInitialShortcuts(to: config) { !taken.contains($0) }

        #expect(config.shortcut(for: .activationShortcut) == Shortcut(keyCode: kVK_ANSI_V, modifiers: [.control, .shift, .command]))
        #expect(config.shortcut(for: .pasteStackShortcut) == Shortcut(keyCode: kVK_ANSI_C, modifiers: [.control, .shift, .command]))
        #expect(config.shortcut(for: .nextPinboardShortcut) == ShortcutDefaults.nextPinboard)
        #expect(config.shortcut(for: .previousPinboardShortcut) == ShortcutDefaults.previousPinboard)
    }

    @Test func withBothChoicesTakenTheShortcutStaysEmptyForGood() {
        ShortcutDefaults.applyInitialShortcuts(to: config) { _ in false }

        #expect(config.shortcut(for: .activationShortcut) == nil)
        #expect(config.shortcut(for: .pasteStackShortcut) == nil)
        #expect(defaults.object(forKey: "activationShortcut") == nil)
        #expect(config.value(for: .isInitialShortcutsMigrationCompleted))

        // A later launch, with everything free, leaves the choice as it was made.
        ShortcutDefaults.applyInitialShortcuts(to: config) { _ in true }

        #expect(config.shortcut(for: .activationShortcut) == nil)
    }

    @Test func eachShortcutChoosesOnItsOwn() {
        ShortcutDefaults.applyInitialShortcuts(to: config) { $0 != ShortcutDefaults.activation }

        #expect(config.shortcut(for: .activationShortcut) == ShortcutDefaults.alternateActivation)
        #expect(config.shortcut(for: .pasteStackShortcut) == ShortcutDefaults.pasteStack)
    }

    @Test func onlyTheSystemWideShortcutsThatAreUnsetAreLookedInto() {
        config.setShortcut(Shortcut(keyCode: kVK_ANSI_P, modifiers: .control), for: .pasteStackShortcut)
        var asked: [Shortcut] = []

        ShortcutDefaults.applyInitialShortcuts(to: config) { shortcut in
            asked.append(shortcut)
            return false
        }

        #expect(asked == [ShortcutDefaults.activation, ShortcutDefaults.alternateActivation])
    }

    @Test func theAlternateIsNotLookedIntoWhenTheFirstChoiceIsFree() {
        var asked: [Shortcut] = []

        ShortcutDefaults.applyInitialShortcuts(to: config) { shortcut in
            asked.append(shortcut)
            return true
        }

        #expect(asked == [ShortcutDefaults.activation, ShortcutDefaults.pasteStack])
    }

    // MARK: Saved shortcuts that something else has at a later launch

    @Test func onlyTheSystemWideShortcutsTheUserHasAreReportedTaken() {
        config.setShortcut(ShortcutDefaults.activation, for: .activationShortcut)
        config.setShortcut(ShortcutDefaults.pasteStack, for: .pasteStackShortcut)
        config.setShortcut(ShortcutDefaults.nextPinboard, for: .nextPinboardShortcut)

        // The panel's own shortcuts are never asked about.
        var asked: [Shortcut] = []
        let taken = ShortcutDefaults.takenShortcuts(in: config) { shortcut in
            asked.append(shortcut)
            return shortcut != ShortcutDefaults.pasteStack
        }

        #expect(taken.map(\.name) == [ConfigKey.pasteStackShortcut.name])
        #expect(asked == [ShortcutDefaults.activation, ShortcutDefaults.pasteStack])
    }

    @Test func noShortcutIsNeverTaken() {
        #expect(ShortcutDefaults.takenShortcuts(in: config) { _ in false }.isEmpty)
    }

    @Test func restoringWritesTheFourShortcutsAndTheTwoModifiers() {
        config.setShortcut(nil, for: .activationShortcut)
        config.setShortcut(Shortcut(keyCode: kVK_ANSI_P, modifiers: .control), for: .nextPinboardShortcut)
        config.set(0x80000, for: .quickPasteModifierFlags)
        config.set(0x40000, for: .plainTextModifierFlags)

        ShortcutDefaults.restore(in: config)

        #expect(config.shortcut(for: .activationShortcut) == ShortcutDefaults.activation)
        #expect(config.shortcut(for: .pasteStackShortcut) == ShortcutDefaults.pasteStack)
        #expect(config.shortcut(for: .nextPinboardShortcut) == ShortcutDefaults.nextPinboard)
        #expect(config.shortcut(for: .previousPinboardShortcut) == ShortcutDefaults.previousPinboard)
        #expect(defaults.integer(forKey: "quickPasteModifierFlags") == 0x100000)
        #expect(defaults.integer(forKey: "plainTextModifierFlags") == 0x20000)
    }
}
