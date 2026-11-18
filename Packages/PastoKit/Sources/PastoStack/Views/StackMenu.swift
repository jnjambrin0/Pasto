import AppKit
import PastoInput

/// The menu of the header's "…" button.
enum StackMenu {
    /// Built anew every time it opens, from the model's state at that moment.
    static func make(for model: StackModel) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false

        let pasteAll = item(StackStrings.pasteAll) { model.pasteAll() }
        // Shown for reference: the shortcut itself is the stack's system-wide hot key.
        pasteAll.keyEquivalent = "v"
        pasteAll.keyEquivalentModifierMask = StackHotKey.pasteAll.shortcut.modifiers
        pasteAll.isEnabled = !model.rows.isEmpty
        menu.addItem(pasteAll)

        let reverseOrder = item(StackStrings.reverseOrder) { model.reverseOrder() }
        reverseOrder.isEnabled = model.rows.count > 1
        menu.addItem(reverseOrder)

        menu.addItem(.separator())

        // While the app-wide setting is on, the stack's own switch can change nothing.
        let plainText = item(StackStrings.pasteAsPlainText) { model.togglePlainText() }
        plainText.state = model.isPlainTextOn ? .on : .off
        plainText.isEnabled = !model.isGlobalPlainTextOn
        menu.addItem(plainText)

        return menu
    }

    private static func item(_ title: String, handler: @escaping () -> Void) -> NSMenuItem {
        let action = MenuAction(handler: handler)
        let item = NSMenuItem(title: title, action: #selector(MenuAction.run), keyEquivalent: "")
        item.target = action
        // A menu item does not retain its target; this makes the action live as long as the item.
        item.representedObject = action
        return item
    }
}

/// The target of a menu item that runs a closure.
private final class MenuAction: NSObject {
    private let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func run() {
        handler()
    }
}
