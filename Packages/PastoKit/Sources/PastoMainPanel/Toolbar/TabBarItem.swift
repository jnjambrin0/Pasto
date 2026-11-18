import PastoCore

/// What the tab bar shows for one list: the clipboard history or a pinboard.
public nonisolated struct TabBarItem: Sendable, Hashable, Identifiable {
    public nonisolated enum Kind: Sendable, Hashable {
        case history
        case pinboard(PinboardColor)
    }

    public var id: ListID
    public var name: String
    public var kind: Kind

    public init(id: ListID, name: String, kind: Kind) {
        self.id = id
        self.name = name
        self.kind = kind
    }
}

extension TabBarItem {
    /// The tab for a stored list. A list without a name shows a default one: the clipboard
    /// history its localized name, a pinboard "Untitled" — the user can leave a pinboard's name
    /// empty, and it is stored empty.
    public init(list: ClipList) {
        let kind: Kind = switch list.attributes {
        case .clipboard: .history
        case .pinboard(let color): .pinboard(color)
        }
        self.init(id: list.id, name: Self.displayName(list.name, kind: kind), kind: kind)
    }

    /// What a tab of `kind` shows for a stored `name`.
    static func displayName(_ name: String, kind: Kind) -> String {
        guard name.isEmpty else { return name }
        return switch kind {
        case .history: ToolbarStrings.historyTab
        case .pinboard: ToolbarStrings.untitledPinboard
        }
    }

    /// The name to create a pinboard with before the user types one.
    public static var untitledPinboardName: String { ToolbarStrings.untitledPinboard }
}
