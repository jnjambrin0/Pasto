import AppKit
import PastoCore

/// Builds the context menus of the tabs and routes what the user picks: commands to
/// `TabMenuActions`, renaming back to the tab bar.
final class TabMenuController: NSObject {
    weak var actions: (any TabMenuActions)?
    /// Called when a tab's menu asks to rename it.
    var onRename: ((ListID) -> Void)?
    /// How many items a list holds; some entries depend on it.
    var itemCount: ((ListID) -> Int)?

    // MARK: - Tab menus

    func makeTabMenu(for tab: TabBarItem) -> NSMenu {
        let menu = makeMenu()
        let rename = NSMenuItem(title: ToolbarStrings.rename, action: #selector(renameTab(_:)), keyEquivalent: "")
        rename.target = self
        rename.representedObject = tab.id
        rename.image = Self.symbol(Self.renameSymbol)
        menu.addItem(rename)

        let isEmpty = (itemCount?(tab.id) ?? 0) == 0
        switch tab.kind {
        case .history:
            // There is nothing to erase in an empty history.
            if !isEmpty {
                menu.addItem(item(ToolbarStrings.eraseHistory, .eraseHistory))
            }
        case .pinboard(let color):
            // The ellipsis announces the confirmation that deleting a pinboard with items asks for.
            menu.addItem(item(isEmpty ? ToolbarStrings.delete : ToolbarStrings.deleteWithConfirmation, .deletePinboard(tab.id)))
            menu.addItem(.separator())
            menu.addItem(colorRow(selected: color, pinboard: tab.id))
        }
        return menu
    }

    private func colorRow(selected: PinboardColor, pinboard: ListID) -> NSMenuItem {
        let row = NSMenuItem()
        row.view = PinboardColorMenuItemView(selectedColor: selected) { [weak self] color in
            self?.actions?.perform(.setPinboardColor(color, of: pinboard))
        }
        return row
    }

    // MARK: - Items

    private func makeMenu() -> NSMenu {
        let menu = NSMenu()
        // The items never disable themselves: every item shown is enabled.
        menu.autoenablesItems = false
        return menu
    }

    // The symbols the items carry.
    private static let renameSymbol = "pencil"
    private static let deleteSymbol = "trash"

    private static func symbol(_ name: String) -> NSImage? {
        NSImage(systemSymbolName: name, accessibilityDescription: nil)
    }

    /// An item that sends `command`. Both commands with an item of their own remove something.
    private func item(_ title: String, _ command: TabMenuCommand) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(performCommand(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = command
        item.image = Self.symbol(Self.deleteSymbol)
        return item
    }

    @objc private func performCommand(_ sender: NSMenuItem) {
        guard let command = sender.representedObject as? TabMenuCommand else { return }
        actions?.perform(command)
    }

    @objc private func renameTab(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? ListID else { return }
        onRename?(id)
    }
}
