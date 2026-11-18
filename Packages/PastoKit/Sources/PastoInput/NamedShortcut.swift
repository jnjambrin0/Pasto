import AppKit
import Carbon.HIToolbox

/// A shortcut together with what it does, as the user knows it: the name a conflict reports.
public struct NamedShortcut: Equatable, Sendable {
    public let name: String
    public let shortcut: Shortcut

    public init(name: String, shortcut: Shortcut) {
        self.name = name
        self.shortcut = shortcut
    }

    /// The Paste Stack's own "Paste All", held while the stack is open. It is no setting, but no
    /// recorded shortcut may take it either.
    public static func pasteStackPasteAll(name: String) -> NamedShortcut {
        NamedShortcut(name: name, shortcut: Shortcut(keyCode: kVK_ANSI_V, modifiers: [.control, .option, .command]))
    }
}
