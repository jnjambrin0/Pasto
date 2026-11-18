import Foundation

/// The stack's user-facing strings. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
nonisolated enum StackStrings {
    static var title: String { localized("stack.title", "Stack") }
    /// Two lines at most: an empty panel has room for no more.
    static var emptyState: String {
        localized("stack.emptyState", "Copied and added items\nline up here to paste in turn")
    }

    /// The first stack ever opened says this above its rows.
    static var firstUseHint: String {
        localized("stack.firstUseHint", "Each copy joins the list; ⌘V pastes them one by one, in order.")
    }

    // MARK: Header buttons

    static var undo: String { localized("stack.button.undo", "Undo") }
    static var more: String { localized("stack.button.more", "More") }
    static var close: String { localized("stack.button.close", "Close") }

    // MARK: Menus

    static var pasteAll: String { localized("stack.menu.pasteAll", "Paste All") }
    static var reverseOrder: String { localized("stack.menu.reverseOrder", "Reverse Order") }
    static var pasteAsPlainText: String { localized("stack.menu.pasteAsPlainText", "Paste as Plain Text") }
    static var delete: String { localized("stack.menu.delete", "Delete") }
    /// VoiceOver actions of a row.
    static var moveUp: String { localized("stack.action.moveUp", "Move Up") }
    static var moveDown: String { localized("stack.action.moveDown", "Move Down") }
    /// What the paste target is called while no application can be named.
    static var currentApplication: String { localized("stack.menu.currentApplication", "current app") }

    static func paste(to application: String) -> String {
        String(localized: "stack.menu.pasteTo", defaultValue: "Paste to \(application)", bundle: .module)
    }

    // MARK: Cards

    static var unknownContent: String { localized("stack.card.unknown", "No preview available") }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
