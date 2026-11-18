import AppKit

/// The "Share" submenu of a card's context menu, filled when it opens rather than when the
/// context menu does: what an item shares is read from the store — and an image decoded — only
/// if the user goes there.
///
/// The entries are the system's: those of the standard Share item of a sharing service picker,
/// moved into this submenu. The picker stays alive with the submenu, since its entries act
/// through it.
final class ShareMenu: NSObject, NSMenuDelegate {
    private let shareableItems: () -> [Any]
    private var picker: NSSharingServicePicker?

    private init(shareableItems: @escaping () -> [Any]) {
        self.shareableItems = shareableItems
    }

    /// An entry whose submenu offers to share what `shareableItems` returns when it opens.
    static func item(shareableItems: @escaping () -> [Any]) -> NSMenuItem {
        let shareMenu = ShareMenu(shareableItems: shareableItems)
        let submenu = NSMenu()
        submenu.delegate = shareMenu
        let item = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        item.submenu = submenu
        // A menu does not retain its delegate; this is what keeps it alive with the entry.
        item.representedObject = shareMenu
        return item
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        guard picker == nil else { return }
        let picker = NSSharingServicePicker(items: shareableItems())
        self.picker = picker
        guard let services = picker.standardShareMenuItem.submenu else { return }
        let entries = services.items
        services.removeAllItems()
        entries.forEach(menu.addItem)
        menu.showsItemImages()
    }
}
