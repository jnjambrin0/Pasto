import PastoCore

/// What an item of a tab's context menu asks for. Renaming is not here: the tab bar handles it
/// itself.
public nonisolated enum TabMenuCommand: Sendable, Hashable {
    // Clipboard history tab
    case eraseHistory

    // Pinboard tab
    case deletePinboard(ListID)
    case setPinboardColor(PinboardColor, of: ListID)
}
