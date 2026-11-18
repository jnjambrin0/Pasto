import Foundation

/// User-visible strings of the app layer: the app menu, the main menu, the on-screen notices and
/// launch alerts. English and Spanish live in `Resources/Localizable.xcstrings`; the English text is
/// repeated here as the fallback.
enum AppStrings {
    // MARK: App menu

    static var aboutPasto: String { localized("menu.more.about", "About Pasto") }
    static var checkForUpdates: String { localized("menu.more.checkForUpdates", "Check for Updates…") }
    static var newTextItem: String { localized("menu.more.newTextItem", "New Text Item") }
    static var settings: String { localized("menu.more.settings", "Settings…") }
    static var quitPasto: String { localized("menu.more.quit", "Quit Pasto") }
    static var pausePasto: String { localized("menu.more.pause", "Pause Pasto") }
    static var pausedShort: String { localized("menu.more.paused", "Paused") }
    static var pause: String { localized("menu.pause.untilResumed", "Pause") }
    static var resume: String { localized("menu.pause.resume", "Resume") }

    /// "Until 18:30".
    static func until(_ time: String) -> String {
        String(localized: "menu.more.until", defaultValue: "Until \(time)", bundle: .module)
    }

    /// "Pause for 15m".
    static func pauseFor(_ duration: String) -> String {
        String(localized: "menu.pause.for", defaultValue: "Pause for \(duration)", bundle: .module)
    }

    // MARK: Help menu

    static var helpMenu: String { localized("menu.help", "Help") }
    static var gettingStarted: String { localized("menu.help.gettingStarted", "Getting Started") }
    static var keyboardShortcuts: String { localized("menu.help.keyboardShortcuts", "Keyboard Shortcuts") }
    /// The panel's guide again.
    static var showTips: String { localized("menu.help.showTips", "Show Tips") }
    static var reportProblem: String { localized("menu.help.reportProblem", "Report a Problem…") }
    static var acknowledgements: String { localized("menu.help.acknowledgements", "Acknowledgements") }

    // MARK: Reporting a problem

    static var reportProblemTitle: String { localized("report.title", "Report a Problem") }
    static var reportProblemMessage: String {
        localized(
            "report.message",
            "Write what happened, what you expected and, if you can, how to make it happen again. The versions of Pasto and macOS are filled in for you. Nothing is sent until you send it."
        )
    }
    static var reportProblemEmail: String { localized("report.email", "Write Email") }
    static var reportProblemContactPage: String { localized("report.contactPage", "Open Contact Page") }
    static var reportProblemShowFiles: String {
        localized("report.showFiles", "Show Pasto’s diagnostic files in Finder, to attach them")
    }
    static var reportProblemSubject: String { localized("report.subject", "Pasto: a problem") }
    static var reportProblemPrompt: String {
        localized("report.prompt", "What happened? What did you expect? How can it be made to happen again?")
    }
    static var cancel: String { localized("alert.cancel", "Cancel") }

    // MARK: Panel

    /// What VoiceOver says as the panel opens: the list on show and how many items it has.
    static func panelAnnouncement(list: String, itemCount: Int) -> String {
        "\(list), \(String(localized: "panel.itemCount", defaultValue: "\(itemCount) items", bundle: .module))"
    }

    // MARK: Main menu

    static var fileMenu: String { localized("mainMenu.file", "File") }
    static var close: String { localized("mainMenu.close", "Close") }
    static var editMenu: String { localized("mainMenu.edit", "Edit") }
    static var undo: String { localized("mainMenu.undo", "Undo") }
    static var redo: String { localized("mainMenu.redo", "Redo") }
    static var cut: String { localized("mainMenu.cut", "Cut") }
    static var copy: String { localized("mainMenu.copy", "Copy") }
    static var paste: String { localized("mainMenu.paste", "Paste") }
    static var selectAll: String { localized("mainMenu.selectAll", "Select All") }
    static var windowMenu: String { localized("mainMenu.window", "Window") }
    static var minimize: String { localized("mainMenu.minimize", "Minimize") }

    // MARK: On-screen notices

    static var copied: String { localized("osd.copied", "Copied") }
    static var enableDirectPaste: String { localized("osd.enableDirectPaste", "Enable Direct Paste") }
    static var paused: String { localized("osd.paused", "Pasto Paused") }
    static var resumed: String { localized("osd.resumed", "Pasto Resumed") }

    // MARK: Launch

    static var storeFailureTitle: String { localized("alert.storeFailure.title", "Pasto can’t open its database") }
    static var quit: String { localized("alert.quit", "Quit") }
    static var storeFailureUnreadable: String {
        localized("alert.storeFailure.unreadable", "The database is damaged or can’t be read. Pasto can set it aside and start with an empty history; nothing is deleted.")
    }
    static var storeFailureMigration: String {
        localized("alert.storeFailure.migration", "The database could not be updated for this version of Pasto. It has been left exactly as it was.")
    }
    static var storeFailureNewerVersion: String {
        localized("alert.storeFailure.newerVersion", "The database was created by a newer version of Pasto. Update Pasto to open it.")
    }
    static var storeFailureStartFresh: String { localized("alert.storeFailure.startFresh", "Set Aside and Start Fresh") }
    static var storeFailureTryAgain: String { localized("alert.storeFailure.tryAgain", "Try Again") }
    static var storeFailureShowInFinder: String { localized("alert.storeFailure.showInFinder", "Show in Finder") }

    // MARK: Menu bar icon

    /// The icon's help tag while capture has no pasteboard access.
    static var pasteboardAccessMissing: String {
        localized("statusItem.pasteboardAccessMissing", "Pasto can’t see what you copy. Open the panel to allow it.")
    }

    // MARK: Moving to Applications

    static var relocationTitle: String { localized("relocation.title", "Move Pasto to the Applications folder?") }
    static var relocationEphemeralMessage: String {
        localized(
            "relocation.message.ephemeral",
            "Pasto is running from a disk image or from where it was downloaded. From there it can’t update itself or open when you log in."
        )
    }
    static var relocationOutsideMessage: String {
        localized(
            "relocation.message.outside",
            "Pasto works best in the Applications folder, where it can update itself and open when you log in."
        )
    }
    static var relocationMove: String { localized("relocation.move", "Move to Applications") }
    static var relocationDontMove: String { localized("relocation.dontMove", "Don’t Move") }
    static var relocationDontAskAgain: String { localized("relocation.dontAskAgain", "Don’t ask again") }
    static var relocationByHandTitle: String { localized("relocation.byHand.title", "Move Pasto to the Applications folder") }
    static var relocationByHandMessage: String {
        localized(
            "relocation.byHand.message",
            "Pasto is running from where it was downloaded, so it can’t update itself or open when you log in. Quit Pasto, drag it to the Applications folder in Finder and open it again from there."
        )
    }
    static var relocationReplaceTitle: String {
        localized("relocation.replace.title", "A copy of Pasto in Applications is open")
    }
    static var relocationReplaceMessage: String {
        localized("relocation.replace.message", "To put this one in its place, that copy will quit and go to the Trash.")
    }
    static var relocationReplace: String { localized("relocation.replace", "Replace") }
    static var relocationCancel: String { localized("relocation.cancel", "Cancel") }
    static var relocationFailureTitle: String { localized("relocation.failure.title", "Pasto couldn’t be moved") }
    /// - Parameter reason: What went wrong, as the system words it.
    static func relocationFailureMessage(_ reason: String) -> String {
        String(
            localized: "relocation.failure.message",
            defaultValue: "\(reason) You can drag Pasto to the Applications folder in Finder and open it again from there.",
            bundle: .module
        )
    }
    static var relocationOtherCopyStillRunning: String {
        localized("relocation.failure.stillRunning", "The other copy of Pasto didn’t quit.")
    }
    static var relocationOK: String { localized("relocation.ok", "OK") }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
