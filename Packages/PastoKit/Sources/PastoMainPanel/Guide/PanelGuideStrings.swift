import Foundation

/// What the panel's guide says. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
enum PanelGuideStrings {
    // MARK: Cards

    static var cardsTitle: String { localized("guide.cards.title", "Everything You Copy") }
    static var cardsMessage: String {
        localized("guide.cards.message", "Return pastes the selected item and Space previews it.")
    }

    /// "⌘1–9 paste one of the first nine."
    static func cardsQuickPaste(_ keys: String) -> String {
        String(localized: "guide.cards.quickPaste", defaultValue: "\(keys) paste one of the first nine.", bundle: .module)
    }

    // MARK: Search

    static var searchTitle: String { localized("guide.search.title", "Search") }
    static var searchMessage: String {
        localized("guide.search.message", "Just start typing, or press ⌘F, to search everything you have copied.")
    }

    // MARK: Pinboards

    static var pinboardsTitle: String { localized("guide.pinboards.title", "Pinboards") }
    static var pinboardsMessage: String {
        localized("guide.pinboards.message", "Pinboards keep items for good. + makes a new one.")
    }

    /// "⌘← and ⌘→ switch tabs."
    static func pinboardsNavigation(previous: String, next: String) -> String {
        String(localized: "guide.pinboards.navigation", defaultValue: "\(previous) and \(next) switch tabs.", bundle: .module)
    }

    // MARK: Suggestions

    static var suggestionsTitle: String { localized("guide.suggestions.title", "Suggestions") }
    static var suggestionsMessage: String {
        localized("guide.suggestions.message", "Puts first what suits the app you are about to paste into.")
    }

    static var suggestionsFirstUseMessage: String {
        localized(
            "guide.suggestions.firstUse",
            "What suits the app you are pasting into comes first. Choose a tab to go back to your history."
        )
    }

    // MARK: "…" menu

    static var moreTitle: String { localized("guide.more.title", "Settings and Help") }
    static var moreMessage: String { localized("guide.more.message", "Settings, pausing and help are in this menu.") }

    /// "Open this panel anytime with ⇧⌘V."
    static func moreActivation(_ shortcut: String) -> String {
        String(localized: "guide.more.activation", defaultValue: "Open this panel anytime with \(shortcut).", bundle: .module)
    }

    /// "⇧⌘C opens the Paste Stack: …"
    static func moreStack(_ shortcut: String) -> String {
        String(
            localized: "guide.more.stack",
            defaultValue: "\(shortcut) opens the Paste Stack: copy several things, then paste them in order.",
            bundle: .module
        )
    }

    // MARK: Buttons and steps

    static var next: String { localized("guide.button.next", "Next") }
    static var done: String { localized("guide.button.done", "Done") }
    static var skip: String { localized("guide.button.skip", "Skip") }
    static var gotIt: String { localized("guide.button.gotIt", "Got It") }

    /// "2 of 5".
    static func step(_ number: Int, of count: Int) -> String {
        String(localized: "guide.step", defaultValue: "\(number) of \(count)", bundle: .module)
    }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
