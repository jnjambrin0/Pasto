import AppKit
import PastoCore
import PastoUI

/// Builds a card's context menu: the entries of an `ItemMenuContent` as menu items, with their
/// titles, symbols and key equivalents.
///
/// The key equivalents are only what the menu shows: with the panel open those keys are
/// answered by `ItemCollectionView`.
enum ItemContextMenu {
    /// What the menu needs besides its entries.
    struct Configuration {
        /// Held to paste as plain text: the modifiers "Paste as Plain Text" shows.
        var plainTextModifierFlags: NSEvent.ModifierFlags
        var createStackKeyEquivalent: KeyEquivalent?
        /// The name of a list, for "Show in …".
        var listName: (ListID) -> String?
        var listSymbol: (ListID) -> String
        var pinSubmenu: NSMenu
        /// The Share entry for the clicked item, whose submenu lists the system's services once
        /// it opens (`ShareMenu`).
        var shareItem: NSMenuItem
        /// The system's Writing Tools entry, whose title and image the menu borrows.
        var writingToolsItem: NSMenuItem?
        /// Runs the entry the user picked. Called when it is picked, not when the menu opens.
        var perform: (ItemMenuEntry) -> Void
    }

    static func make(entries: [ItemMenuEntry], configuration: Configuration) -> NSMenu {
        let menu = NSMenu()
        // Every entry is shown enabled: the ones that cannot act say so when picked.
        menu.autoenablesItems = false

        var isFirstShowIn = true
        for entry in entries {
            let item = makeItem(for: entry, configuration)
            if case .showIn = entry {
                // Only the first list gets the key: that is the one ⌘G jumps to.
                if !isFirstShowIn { item.keyEquivalent = "" }
                isFirstShowIn = false
            }
            menu.addItem(item)
        }
        return menu
    }

    private static func makeItem(for entry: ItemMenuEntry, _ configuration: Configuration) -> NSMenuItem {
        func item(_ title: String, _ symbolName: String?, key: String = "", _ modifiers: NSEvent.ModifierFlags = []) -> NSMenuItem {
            let item = MenuItemHandler.item(title: title, keyEquivalent: key) { configuration.perform(entry) }
            item.keyEquivalentModifierMask = modifiers
            item.image = symbolName.flatMap(symbol)
            return item
        }

        switch entry {
        case .separator:
            return .separator()
        case .open(let applicationName):
            let title = applicationName.map(ItemActionStrings.openWith) ?? ItemActionStrings.open
            return item(title, "arrow.up.forward.square", key: "o", .command)
        case .revealInFinder:
            return item(ItemActionStrings.revealInFinder, "finder")
        case .showIn(let list):
            let title = ItemActionStrings.showIn(configuration.listName(list) ?? "")
            return item(title, configuration.listSymbol(list), key: "g", .command)
        case .paste(let applicationName):
            let title = ItemActionStrings.pasteTo(applicationName ?? ItemActionStrings.currentApplication)
            return item(title, "doc.on.clipboard", key: "\r")
        case .pasteAsPlainText:
            return item(ItemActionStrings.pasteAsPlainText, "text.justify.leading", key: "\n", configuration.plainTextModifierFlags)
        case .copy:
            return item(ItemActionStrings.copy, "doc.on.doc", key: "c", .command)
        case .createStack:
            let shortcut = configuration.createStackKeyEquivalent
            return item(ItemActionStrings.createStack, "square.2.stack.3d", key: shortcut?.character ?? "", shortcut?.modifiers ?? [])
        case .edit:
            return item(ItemActionStrings.edit, "pencil", key: "e", .command)
        case .writingTools:
            let item = item(configuration.writingToolsItem?.title ?? "", nil)
            item.image = configuration.writingToolsItem?.image
            return item
        case .rename:
            return item(ItemActionStrings.rename, "pencil.and.ellipsis.rectangle", key: "r", .command)
        case .delete:
            return item(ItemActionStrings.delete, "trash", key: "\u{8}")
        case .pin:
            let item = NSMenuItem(title: ItemActionStrings.pin, action: nil, keyEquivalent: "")
            item.image = symbol("pin")
            item.submenu = configuration.pinSubmenu
            return item
        case .preview:
            return item(ItemActionStrings.preview, "eye", key: " ")
        case .share:
            let item = configuration.shareItem
            item.title = ItemActionStrings.share
            item.image = symbol("square.and.arrow.up")
            return item
        }
    }

    /// A symbol the system does not have still leaves a mark, rather than an entry out of line.
    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)
    }
}
