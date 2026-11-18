import AppKit

/// The main menu. Pasto is a menu bar agent and never shows a menu bar of its own, but key
/// equivalents such as ⌘W, ⌘Q, ⌘T or the editing shortcuts in text fields only work if a main
/// menu defines them.
enum MainMenu {
    static func make(appMenu: AppMenu) -> NSMenu {
        let mainMenu = NSMenu()
        mainMenu.addItem(submenuItem("Pasto", appMenu.makeMenu()))

        let file = NSMenu()
        file.addItem(withTitle: AppStrings.close, action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        mainMenu.addItem(submenuItem(AppStrings.fileMenu, file))

        let edit = NSMenu()
        edit.addItem(withTitle: AppStrings.undo, action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: AppStrings.redo, action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: AppStrings.cut, action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: AppStrings.copy, action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: AppStrings.paste, action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: AppStrings.selectAll, action: #selector(NSResponder.selectAll(_:)), keyEquivalent: "a")
        mainMenu.addItem(submenuItem(AppStrings.editMenu, edit))

        let window = NSMenu()
        window.addItem(withTitle: AppStrings.minimize, action: #selector(NSWindow.miniaturize(_:)), keyEquivalent: "m")
        mainMenu.addItem(submenuItem(AppStrings.windowMenu, window))
        return mainMenu
    }

    /// The menu while onboarding runs: only a way to quit.
    static func makeForOnboarding() -> NSMenu {
        let mainMenu = NSMenu()
        let app = NSMenu()
        app.addItem(withTitle: AppStrings.quitPasto, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        mainMenu.addItem(submenuItem("Pasto", app))
        return mainMenu
    }

    private static func submenuItem(_ title: String, _ submenu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        submenu.title = title
        item.submenu = submenu
        return item
    }
}
