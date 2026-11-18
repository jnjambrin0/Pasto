import PastoCore

/// One line of a card's context menu.
nonisolated enum ItemMenuEntry: Hashable, Sendable {
    /// `applicationName` is the application that opens the item's file, when it is known.
    case open(applicationName: String?)
    case revealInFinder
    case showIn(ListID)
    /// `applicationName` is the application the paste goes to, when it is known.
    case paste(applicationName: String?)
    case pasteAsPlainText
    case copy
    case createStack
    case edit
    case writingTools
    case rename
    case delete
    case pin
    case preview
    case share
    case separator
}

/// Which entries a card's context menu has, and in which order. The facts it is decided from are
/// about the card that was clicked, whatever else is selected.
nonisolated struct ItemMenuContent: Sendable {
    /// The clicked item is a link, or files whose first one still exists.
    var canOpen = false
    /// The application the system would open the clicked item's first file with.
    var openingApplicationName: String?
    var isFiles = false
    /// The other lists the selected item is in; see `ShowInLists`.
    var showInLists: [ListID] = []
    /// The application that owns the menu bar: where a paste would land.
    var pasteTargetName: String?
    /// The "always paste as plain text" setting: with it on, the one paste entry is the plain one.
    var isAlwaysPlainText = false

    // Entries of features the app may not have connected; an entry nobody answers is left out.
    var offersShowIn = false
    var offersCreateStack = false
    var offersEdit = false
    var offersWritingTools = false
    var offersPreview = false

    var entries: [ItemMenuEntry] {
        var entries: [ItemMenuEntry] = []

        if canOpen { entries.append(.open(applicationName: openingApplicationName)) }
        if isFiles { entries.append(.revealInFinder) }
        if offersShowIn { entries += showInLists.map(ItemMenuEntry.showIn) }
        if !entries.isEmpty { entries.append(.separator) }

        entries.append(.paste(applicationName: pasteTargetName))
        if !isAlwaysPlainText { entries.append(.pasteAsPlainText) }
        entries.append(.copy)
        if offersCreateStack { entries.append(.createStack) }
        entries.append(.separator)

        if offersEdit { entries.append(.edit) }
        if offersWritingTools { entries.append(.writingTools) }
        entries += [.rename, .delete, .separator, .pin, .separator]

        if offersPreview { entries.append(.preview) }
        entries.append(.share)
        return entries
    }
}

/// The lists "Show in …" can jump to: with exactly one item selected, the history if the item is
/// in it, then the item's pinboard — leaving out the list on show, if the strip shows one (search
/// results are in none).
nonisolated enum ShowInLists {
    static func lists(for selection: [Item], shownList: ListID?) -> [ListID] {
        guard selection.count == 1, let item = selection.first else { return [] }
        let history: ListID? = item.timestamp == nil ? nil : .clipboard
        return [history, item.listID].compactMap { $0 }.filter { $0 != shownList }
    }
}

extension ItemType {
    /// Whether an item of this type has content an editor can change: files and unknown
    /// content never do.
    nonisolated var hasEditableContent: Bool {
        switch self {
        case .image, .color, .link, .text: true
        case .files, .unknown: false
        }
    }
}
