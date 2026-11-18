import Foundation

/// A card shown before the first item of the strip: something Pasto suggests the user do, with
/// a button that does it. Cards are stored whole, texts included, so they read in the language
/// they were added in.
public nonisolated struct NoticeCard: Codable, Hashable, Sendable, Identifiable {
    /// What a card's button asks the app to do.
    public enum Command: String, Codable, Sendable {
        case enableOpenAtLogin
        case enableDirectPaste
        /// Walk the user through setting pasteboard access to "always allow".
        case allowPasteboardAccess
        /// The card only informs: its button puts it away.
        case acknowledgeOtherClipboardManagers
        /// Open Settings on its Shortcuts pane, where a shortcut something else has can change.
        case openShortcutSettings
        /// Open System Settings › General › Storage, where the Mac's disk can be freed up.
        case openStorageSettings
    }

    public struct Action: Codable, Hashable, Sendable {
        public let symbol: String?
        public let title: String
        public let command: Command

        public init(symbol: String? = nil, title: String, command: Command) {
            self.symbol = symbol
            self.title = title
            self.command = command
        }
    }

    /// One card per identifier at most.
    public let id: String
    /// An SF Symbol.
    public let symbol: String
    public let title: String
    public let description: String?
    public let action: Action

    public init(id: String, symbol: String, title: String, description: String? = nil, action: Action) {
        self.id = id
        self.symbol = symbol
        self.title = title
        self.description = description
        self.action = action
    }
}
