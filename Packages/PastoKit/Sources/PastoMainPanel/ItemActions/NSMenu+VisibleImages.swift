import AppKit

extension NSMenu {
    /// From macOS 27 menus decide on their own whether an item's image shows, and usually hide
    /// it. The Pin and Share submenus of a card ask for every image they have to show: a
    /// pinboard's colour dot and a sharing service's icon are what tell the entries apart.
    func showsItemImages() {
        for item in items where item.image != nil {
            item.preferredImageVisibility = .visible
        }
    }
}
