import AppKit
import PastoCore

/// What the preview asks the rest of the app to do. None of it can live in this module: the
/// menus and the sharing belong to the main panel, and opening addresses and switching lists
/// to the app.
public struct PreviewHandlers {
    /// The pinboard menu of an item — the same one its card offers under "Pin" — which the
    /// preview's Pin button opens. `nil` when there is nothing to offer.
    public var pinMenu: (ItemID) -> NSMenu?
    /// Shows the sharing picker for an item next to the given view, the preview's Share button.
    public var share: (ItemID, _ anchor: NSView) -> Void
    /// Opens an address outside Pasto.
    public var open: (URL) -> Void
    /// The user left for another application from the preview (a page opened in the browser, a
    /// file shown in the Finder): the main panel should close if it is open.
    public var closePanel: () -> Void
    /// Shows the main panel on a list: where an item was just created. The panel is closed by
    /// then — the New Text Item window took the focus — so selecting the list is not enough: the
    /// panel has to open on it.
    public var showList: (ListID) -> Void
    /// Asks the page at an address for its title, icon and image and gives them to the link
    /// item, whose address was just edited (`HistoryManager.fetchLinkMetadata`). Without it an
    /// edited link keeps only its title.
    public var fetchLinkMetadata: ((URL, ItemID) -> Void)?

    public init(
        pinMenu: @escaping (ItemID) -> NSMenu?,
        share: @escaping (ItemID, _ anchor: NSView) -> Void,
        open: @escaping (URL) -> Void,
        closePanel: @escaping () -> Void,
        showList: @escaping (ListID) -> Void,
        fetchLinkMetadata: ((URL, ItemID) -> Void)? = nil
    ) {
        self.pinMenu = pinMenu
        self.share = share
        self.open = open
        self.closePanel = closePanel
        self.showList = showList
        self.fetchLinkMetadata = fetchLinkMetadata
    }
}
