/// The panes, in the order the sidebar lists them. The app names one to open Settings on it
/// (`SettingsWindowController.show(_:)`).
public enum SettingsPane: CaseIterable, Identifiable, Sendable {
    case general
    case intelligence
    case privacy
    case shortcuts

    public var id: Self { self }

    /// The panes the sidebar lists. Intelligence holds only suggestions, so a Mac that cannot run
    /// them has no Intelligence pane rather than an empty one.
    static func listed(hasSuggestions: Bool) -> [SettingsPane] {
        allCases.filter { $0 != .intelligence || hasSuggestions }
    }

    var title: String {
        switch self {
        case .general: SettingsStrings.generalTitle
        case .intelligence: SettingsStrings.intelligenceTitle
        case .privacy: SettingsStrings.privacyTitle
        case .shortcuts: SettingsStrings.shortcutsTitle
        }
    }

    var symbolName: String {
        switch self {
        case .general: "gearshape"
        case .intelligence: "sparkles"
        case .privacy: "hand.raised"
        case .shortcuts: "keyboard"
        }
    }
}
