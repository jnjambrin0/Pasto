import Foundation
@testable import PastoOnboarding
import PastoInput
import Testing

/// The list behind the initial shortcuts and the notice of another clipboard manager.
struct KnownClipboardManagerTests {
    private let list = [
        KnownClipboardManager(name: "Paste", bundleIdentifiers: ["com.wiheads.paste", "com.wiheads.paste-direct"], shortcuts: []),
        KnownClipboardManager(name: "Maccy", bundleIdentifiers: ["org.p0deje.Maccy"], shortcuts: []),
    ]

    @Test func theBundledListNamesPasteWithItsShortcuts() throws {
        let paste = try #require(KnownClipboardManager.all.first { $0.name == "Paste" })

        #expect(Set(paste.bundleIdentifiers) == ["com.wiheads.paste", "com.wiheads.paste-direct", "com.wiheads.paste-setapp"])
        #expect(paste.shortcuts == [ShortcutDefaults.activation, ShortcutDefaults.pasteStack])
        #expect(KnownClipboardManager.all.contains { $0.bundleIdentifiers == ["org.p0deje.Maccy"] })
    }

    @Test func noManagerOfTheBundledListUsesTheAlternateShortcuts() {
        let shortcuts = KnownClipboardManager.all.flatMap(\.shortcuts)

        #expect(!shortcuts.contains(ShortcutDefaults.alternateActivation))
        #expect(!shortcuts.contains(ShortcutDefaults.alternatePasteStack))
    }

    @Test func runningManagersComeInTheListsOrderAndOnce() {
        let running = KnownClipboardManager.running(
            among: ["com.apple.finder", "org.p0deje.Maccy", "com.wiheads.paste", "com.wiheads.paste-direct", nil],
            in: list
        )

        #expect(running.map(\.name) == ["Paste", "Maccy"])
    }

    @Test func bundleIdentifiersCompareWithoutCase() {
        #expect(KnownClipboardManager.running(among: ["ORG.P0DEJE.MACCY"], in: list).map(\.name) == ["Maccy"])
    }

    @Test func nothingKnownRunningIsAnEmptyList() {
        #expect(KnownClipboardManager.running(among: ["com.apple.finder", nil], in: list).isEmpty)
    }

    @Test func anUnreadableListIsEmpty() throws {
        let file = FileManager.default.temporaryDirectory.appending(path: "KnownClipboardManagers-\(UUID().uuidString).json")
        try Data("not a list".utf8).write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }

        #expect(KnownClipboardManager.load(from: file).isEmpty)
        #expect(KnownClipboardManager.load(from: nil).isEmpty)
    }
}
