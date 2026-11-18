import AppKit

/// The app menu: shown from the menu bar icon, from the panel's "…" button and as the first menu
/// of the main menu, which is what makes its key equivalents work while the panel is key. It is
/// rebuilt every time it is shown, so its titles always reflect the current state.
final class AppMenu {
    /// What the Help submenu does.
    struct HelpActions {
        /// Shows the welcome screens again.
        let showGettingStarted: () -> Void
        /// Opens Settings on its Shortcuts pane.
        let showKeyboardShortcuts: () -> Void
        let reportProblem: () -> Void
        let showAcknowledgements: () -> Void
        /// Shows the panel's tips again; without it the entry is not there.
        var showTips: (() -> Void)?
    }

    private let pauseController: PauseController

    private let showAbout: () -> Void
    private let checkForUpdates: () -> Void
    private let canCheckForUpdates: () -> Bool
    private let showSettings: () -> Void
    private let createTextItem: () -> Void
    private let help: HelpActions

    init(
        pauseController: PauseController,
        showAbout: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void,
        canCheckForUpdates: @escaping () -> Bool,
        showSettings: @escaping () -> Void,
        createTextItem: @escaping () -> Void,
        help: HelpActions
    ) {
        self.pauseController = pauseController
        self.showAbout = showAbout
        self.checkForUpdates = checkForUpdates
        self.canCheckForUpdates = canCheckForUpdates
        self.showSettings = showSettings
        self.createTextItem = createTextItem
        self.help = help
    }

    func makeMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(AppStrings.aboutPasto, symbol: "info.circle", action: showAbout))
        // Dimmed while a check or an update is under way, and on runs without updates. Validated
        // each time the menu opens.
        menu.addItem(item(AppStrings.checkForUpdates, symbol: "gear.badge", isEnabled: canCheckForUpdates, action: checkForUpdates))
        menu.addItem(.separator())
        menu.addItem(item(AppStrings.newTextItem, symbol: "square.and.pencil", keyEquivalent: "n", action: createTextItem))
        menu.addItem(item(AppStrings.settings, symbol: "gear", keyEquivalent: ",", action: showSettings))
        menu.addItem(.separator())

        let helpItem = NSMenuItem(title: AppStrings.helpMenu, action: nil, keyEquivalent: "")
        helpItem.image = NSImage(systemSymbolName: "questionmark.circle", accessibilityDescription: nil)
        helpItem.submenu = makeHelpMenu()
        menu.addItem(helpItem)
        menu.addItem(.separator())

        let pause = NSMenuItem(title: pauseController.menuTitle, action: nil, keyEquivalent: "")
        pause.image = NSImage(systemSymbolName: "pause.circle", accessibilityDescription: nil)
        pause.submenu = makePauseMenu()
        menu.addItem(pause)

        let quit = NSMenuItem(title: AppStrings.quitPasto, action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.image = NSImage(systemSymbolName: "xmark.app", accessibilityDescription: nil)
        menu.addItem(quit)
        return menu
    }

    /// Getting started, the panel's tips and the shortcuts are shown in Pasto itself; a problem
    /// is reported by the user, with the versions filled in and nothing sent by Pasto.
    private func makeHelpMenu() -> NSMenu {
        let menu = NSMenu()
        menu.addItem(item(AppStrings.gettingStarted, symbol: "flag", action: help.showGettingStarted))
        if let showTips = help.showTips {
            menu.addItem(item(AppStrings.showTips, symbol: "lightbulb", action: showTips))
        }
        menu.addItem(item(AppStrings.keyboardShortcuts, symbol: "keyboard", action: help.showKeyboardShortcuts))
        menu.addItem(.separator())
        menu.addItem(item(AppStrings.reportProblem, symbol: "paperplane", action: help.reportProblem))
        menu.addItem(.separator())
        menu.addItem(item(AppStrings.acknowledgements, symbol: "doc.text", action: help.showAcknowledgements))
        return menu
    }

    /// Also what the pause indicator in the panel's toolbar opens.
    func makePauseMenu() -> NSMenu {
        let menu = NSMenu()
        let toggleTitle = pauseController.isPaused ? AppStrings.resume : AppStrings.pause
        menu.addItem(item(toggleTitle, symbol: "pause.circle", keyEquivalent: "t") { [pauseController] in
            pauseController.toggle()
        })
        menu.addItem(.separator())

        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute]
        for duration in PauseController.durations {
            let title = formatter.string(from: duration).map(AppStrings.pauseFor) ?? AppStrings.pause
            // 15 and 30 minutes, then 1, 3 and 8 hours: the symbol shows the number.
            let number = duration < 3_600 ? Int(duration / 60) : Int(duration / 3_600)
            menu.addItem(item(title, symbol: "\(number).circle") { [pauseController] in
                pauseController.pause(for: duration)
            })
        }
        return menu
    }

    private func item(
        _ title: String,
        symbol: String,
        keyEquivalent: String = "",
        isEnabled: @escaping () -> Bool = { true },
        action: @escaping () -> Void
    ) -> NSMenuItem {
        let handler = MenuActionHandler(action, isEnabled: isEnabled)
        let item = NSMenuItem(title: title, action: #selector(MenuActionHandler.run), keyEquivalent: keyEquivalent)
        item.target = handler
        // An item does not retain its target; this is what keeps the handler alive with it.
        item.representedObject = handler
        item.image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)
        return item
    }
}

/// Runs a closure as the action of a menu item, and says whether the item is enabled.
private final class MenuActionHandler: NSObject, NSMenuItemValidation {
    private let action: () -> Void
    private let isEnabled: () -> Bool

    init(_ action: @escaping () -> Void, isEnabled: @escaping () -> Bool) {
        self.action = action
        self.isEnabled = isEnabled
    }

    @objc func run() {
        action()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        isEnabled()
    }
}
