import AppKit

/// Runs a closure as the action of a menu item. For menus that are built, shown once and thrown
/// away, where there is no longer-lived object to be the target.
final class MenuItemHandler: NSObject {
    private let action: () -> Void

    private init(_ action: @escaping () -> Void) {
        self.action = action
    }

    @objc private func run() {
        action()
    }

    /// A menu item that runs `action` when chosen.
    static func item(title: String, keyEquivalent: String = "", action: @escaping () -> Void) -> NSMenuItem {
        let handler = MenuItemHandler(action)
        let item = NSMenuItem(title: title, action: #selector(run), keyEquivalent: keyEquivalent)
        item.target = handler
        // An item does not retain its target; this is what keeps the handler alive with it.
        item.representedObject = handler
        return item
    }
}
