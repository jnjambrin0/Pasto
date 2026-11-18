import Foundation
import PastoCore
import PastoFoundation

/// Pasto's welcome content: three notes in the history, and a red pinboard with a welcome note
/// followed by three links — getting started, help, news.
nonisolated enum WelcomeContentCatalog {
    /// Getting started: the website's home page.
    static let websiteURL = SupportLinks.website
    /// Help: the contact page, without the versions a problem report adds.
    static let helpURL = SupportLinks.website.appending(path: "contact")
    /// News: the notes of every version.
    static let releasesURL = SupportLinks.website.appending(path: "releases")

    /// The pinboard's colour: the first one, red.
    static let pinboardColor = PinboardColor.red

    /// - Parameters:
    ///   - activationShortcut: The shortcut that opens Pasto, as the user reads it; `nil` if
    ///     there is none.
    ///   - application: Pasto itself, which the items are credited to.
    static func content(
        strings: WelcomeContentStrings,
        activationShortcut: String?,
        application: FrontmostApplication?
    ) -> WelcomeContent {
        WelcomeContent(
            historyEntries: [
                .note(title: strings.pasteTitle, text: strings.pasteText(shortcut: activationShortcut)),
                .note(title: strings.searchTitle, text: strings.searchText),
                .note(title: strings.pinTitle, text: strings.pinText),
            ],
            pinboardName: strings.pinboardName,
            pinboardColor: pinboardColor,
            pinboardEntries: [
                .note(title: strings.welcomeTitle, text: strings.welcomeText),
                .link(title: strings.websiteTitle, url: websiteURL, pageTitle: strings.websitePageTitle),
                .link(title: strings.helpTitle, url: helpURL, pageTitle: strings.helpPageTitle),
                .link(title: strings.releasesTitle, url: releasesURL, pageTitle: strings.releasesPageTitle),
            ],
            application: application
        )
    }
}
