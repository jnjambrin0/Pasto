import Foundation
import PastoCore

/// The toolbar's user-facing strings. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
enum ToolbarStrings {
    // MARK: Buttons

    static var suggestionsButton: String { localized("toolbar.button.suggestions", "Suggestions") }
    static var searchButton: String { localized("toolbar.button.search", "Search") }
    static var newPinboardButton: String { localized("toolbar.button.newPinboard", "New Pinboard") }
    static var moreButton: String { localized("toolbar.button.more", "More") }

    /// What the suggestions button says under the pointer.
    static var suggestionsToolTip: String {
        localized("toolbar.toolTip.suggestions", "Suggestions for the app you are pasting into")
    }

    /// What "…" says under the pointer.
    static var moreToolTip: String { localized("toolbar.toolTip.more", "Settings, Pause and Help") }

    /// What the magnifying glass says under the pointer, with its shortcut.
    static func searchToolTip(shortcut: String) -> String {
        String(localized: "toolbar.toolTip.search", defaultValue: "Search (\(shortcut))", bundle: .module)
    }

    /// What "+" says under the pointer, with its shortcut.
    static func createPinboardToolTip(shortcut: String) -> String {
        String(localized: "toolbar.toolTip.createPinboard", defaultValue: "Create Pinboard (\(shortcut))", bundle: .module)
    }

    // MARK: Tabs

    static var historyTab: String { localized("tabs.history", "Clipboard") }
    static var untitledPinboard: String { localized("tabs.untitledPinboard", "Untitled") }

    /// How many items a list holds, as a tab's tooltip says it.
    static func itemCount(_ count: Int) -> String {
        String(localized: "tabs.itemCount", defaultValue: "\(count) items", bundle: .module)
    }

    /// What VoiceOver says when the keyboard moves to a tab: its name and how many items its
    /// list holds, as the panel says it when it opens.
    static func tabAnnouncement(name: String, itemCount count: Int) -> String {
        "\(name), \(itemCount(count))"
    }

    /// What a tab says under the pointer: how many items its list holds and the two shortcuts
    /// that move between tabs.
    static func tabToolTip(itemCount count: Int, previousShortcut: String, nextShortcut: String) -> String {
        String(
            localized: "tabs.toolTip",
            defaultValue: "\(itemCount(count)) (\(previousShortcut), \(nextShortcut) to navigate)",
            bundle: .module
        )
    }

    // MARK: Tab menus

    /// The row of colour swatches of a pinboard's menu, for VoiceOver.
    static var pinboardColor: String { localized("pinboard.color.title", "Color") }

    /// A swatch of that row, for VoiceOver.
    static func colorName(_ color: PinboardColor) -> String {
        switch color {
        case .red: localized("pinboard.color.red", "Red")
        case .orange: localized("pinboard.color.orange", "Orange")
        case .yellow: localized("pinboard.color.yellow", "Yellow")
        case .green: localized("pinboard.color.green", "Green")
        case .blue: localized("pinboard.color.blue", "Blue")
        case .purple: localized("pinboard.color.purple", "Purple")
        case .pink: localized("pinboard.color.pink", "Pink")
        case .gray: localized("pinboard.color.gray", "Gray")
        }
    }

    static var rename: String { localized("menu.tab.rename", "Rename") }
    static var eraseHistory: String { localized("menu.tab.eraseHistory", "Erase History…") }
    static var delete: String { localized("menu.tab.delete", "Delete") }
    static var deleteWithConfirmation: String { localized("menu.tab.deleteWithConfirmation", "Delete…") }

    // MARK: Confirmations

    static var eraseHistoryTitle: String { localized("alert.eraseHistory.title", "Erase your clipboard history?") }
    static var eraseHistoryMessage: String {
        localized("alert.eraseHistory.message", "Pinned items and pinboards are kept. This can’t be undone.")
    }
    static var erase: String { localized("alert.eraseHistory.confirm", "Erase") }

    static func deletePinboardTitle(_ name: String) -> String {
        String(localized: "alert.deletePinboard.title", defaultValue: "Delete the pinboard “\(name)”?", bundle: .module)
    }
    static var deletePinboardMessage: String {
        localized(
            "alert.deletePinboard.message",
            "Items that are only on it are deleted too; the ones in your clipboard history stay there. This can’t be undone."
        )
    }
    static var cancel: String { localized("alert.cancel", "Cancel") }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
