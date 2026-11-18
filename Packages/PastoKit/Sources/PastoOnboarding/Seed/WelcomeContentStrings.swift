import Foundation

/// The texts of the welcome content. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
///
/// Read once, when the content is stored: the items keep the language the app had then.
nonisolated struct WelcomeContentStrings: Sendable {
    private let bundle: Bundle
    private let locale: Locale

    /// The texts in the language the app is showing.
    init() {
        bundle = .module
        locale = .autoupdatingCurrent
    }

    /// The texts in one given language, whatever the user's preferences are. `nil` if the module
    /// has no localization for it.
    init?(languageCode: String) {
        guard let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        self.bundle = bundle
        locale = Locale(identifier: languageCode)
    }

    // MARK: Pinboard

    var pinboardName: String { string("welcome.pinboard.name", "Pasto Links") }

    // MARK: History notes

    var pasteTitle: String { string("welcome.paste.title", "Paste Again") }

    /// - Parameter shortcut: The activation shortcut as the user reads it; `nil` when there is
    ///   none, and the note points to the menu bar icon instead.
    func pasteText(shortcut: String?) -> String {
        guard let shortcut else {
            return string(
                "welcome.paste.textWithoutShortcut",
                "Everything you copy is kept here, newest first.\n\nOpen Pasto from its icon in the menu bar, choose an item with the arrow keys and press Return to paste it. Press Space for a closer look first."
            )
        }
        let format = string(
            "welcome.paste.text",
            "Everything you copy is kept here, newest first.\n\nPress %@ in any app to open Pasto, choose an item with the arrow keys and press Return to paste it. Press Space for a closer look first."
        )
        return String(format: format, locale: locale, shortcut)
    }

    var searchTitle: String { string("welcome.search.title", "Find It Fast") }
    var searchText: String {
        string(
            "welcome.search.text",
            "With Pasto open, just start typing to search everything you’ve copied.\n\nChoose one of the suggestions that appear as you type to see only what came from one app, or only links, images or files."
        )
    }

    var pinTitle: String { string("welcome.pin.title", "Keep What Matters") }
    var pinText: String {
        string(
            "welcome.pin.text",
            "Right-click an item and choose Pin to keep it on a pinboard, or drag it onto a pinboard’s tab.\n\nPinned items stay put when older copies leave the history."
        )
    }

    // MARK: Pinboard items

    var welcomeTitle: String { string("welcome.note.title", "Welcome to Pasto") }
    var welcomeText: String {
        string(
            "welcome.note.text",
            "The links on this pinboard lead to Pasto’s website, to help when you need it and to what’s new in each version.\n\nOpen one with ⌘O, or with Open in its right-click menu. The pinboard is yours: rename it, add to it or delete it whenever you like."
        )
    }

    var websiteTitle: String { string("welcome.website.title", "Get to Know Pasto") }
    var websitePageTitle: String { string("welcome.website.pageTitle", "See everything Pasto can do") }

    var helpTitle: String { string("welcome.help.title", "Need a Hand?") }
    var helpPageTitle: String { string("welcome.help.pageTitle", "Ask a question or report a problem") }

    var releasesTitle: String { string("welcome.releases.title", "What’s New") }
    var releasesPageTitle: String { string("welcome.releases.pageTitle", "Read the notes of every version") }

    private func string(_ key: String, _ english: String) -> String {
        bundle.localizedString(forKey: key, value: english, table: nil)
    }
}
