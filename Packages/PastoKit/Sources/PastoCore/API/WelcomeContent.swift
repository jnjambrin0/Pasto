import Foundation

/// What a new installation finds in Pasto when its welcome flow ends: a few notes in the
/// history and a pinboard holding a note and some links. `WritingContext.seedWelcomeContent(_:)`
/// stores it.
public struct WelcomeContent: Sendable {
    /// One item of the welcome content.
    public enum Entry: Sendable, Hashable {
        /// A text item. `title` is the name its card shows; `text` is what it holds.
        case note(title: String, text: String)
        /// A link. `title` is the name its card shows; `pageTitle` is what the preview says about
        /// the page, there from the start so that the card needs no network.
        case link(title: String, url: URL, pageTitle: String)
    }

    /// The history's notes in the order the history shows them: the first one is the newest.
    public var historyEntries: [Entry]
    public var pinboardName: String
    public var pinboardColor: PinboardColor
    /// The pinboard's items in the order it shows them.
    public var pinboardEntries: [Entry]
    /// The application the items are credited to — Pasto itself —, whose icon also stands for
    /// the links' pages. Without one, or without its icon, the items have no source and the
    /// links show the generic symbol until something fills them in.
    public var application: FrontmostApplication?

    public init(
        historyEntries: [Entry],
        pinboardName: String,
        pinboardColor: PinboardColor,
        pinboardEntries: [Entry],
        application: FrontmostApplication?
    ) {
        self.historyEntries = historyEntries
        self.pinboardName = pinboardName
        self.pinboardColor = pinboardColor
        self.pinboardEntries = pinboardEntries
        self.application = application
    }
}
