import Foundation
import PastoInput

/// The Settings window's user-facing strings. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
enum SettingsStrings {
    // MARK: Panes

    static var windowTitle: String { localized("window.title", "Settings") }
    static var generalTitle: String { localized("pane.general", "General") }
    static var intelligenceTitle: String { localized("pane.intelligence", "Intelligence") }
    static var privacyTitle: String { localized("pane.privacy", "Privacy") }
    static var shortcutsTitle: String { localized("pane.shortcuts", "Shortcuts") }

    // MARK: General

    static var openAtLogin: String { localized("general.openAtLogin", "Open at login") }
    /// The pill under "Open at login" when macOS blocks it or waits for approval.
    static var allowInLoginItems: String { localized("general.openAtLogin.allow", "Allow in Login Items settings") }
    static var loginItemBlocked: String {
        localized("general.openAtLogin.blocked", "macOS isn’t letting Pasto open at login. Allow it in System Settings › General › Login Items.")
    }
    static var soundEffects: String { localized("general.soundEffects", "Sound effects") }

    // MARK: Paste items

    static var pasteItemsTitle: String { localized("pasteItems.title", "Paste items") }
    static var pasteToActiveApp: String { localized("pasteItems.activeApp", "Into the active app") }
    static var pasteToActiveAppInfo: String {
        localized("pasteItems.activeApp.info", "Choosing an item pastes it straight into the app you are using.")
    }
    static var pasteToClipboard: String { localized("pasteItems.clipboard", "To the clipboard") }
    static var pasteToClipboardInfo: String {
        localized("pasteItems.clipboard.info", "Choosing an item only copies it, ready for you to paste.")
    }
    static var allowAccessibilityAccess: String {
        localized("pasteItems.allowAccessibility", "Allow access to paste")
    }
    static var alwaysPastePlainText: String { localized("pasteItems.plainText", "Always paste as plain text") }

    // MARK: Keep history

    static var keepHistoryTitle: String { localized("history.title", "Keep history") }
    static var forever: String { localized("history.forever", "Forever") }
    static var unlimited: String { localized("history.unlimited", "Unlimited") }
    static var unlimitedWarning: String {
        localized("history.unlimitedWarning", "A history without a limit can take up a lot of disk space over time.")
    }
    static var eraseHistory: String { localized("history.erase", "Erase History") }
    static var reduceHistoryTitle: String {
        localized("alert.reduceHistory.title", "Some items are older than the new limit. Delete them and apply the limit?")
    }
    static var eraseHistoryTitle: String { localized("alert.eraseHistory.title", "Erase your clipboard history?") }
    static var historyDeletionMessage: String {
        localized("alert.historyDeletion.message", "Pinned items and pinboards are kept. This can’t be undone.")
    }
    static var erase: String { localized("alert.erase", "Erase") }
    static var delete: String { localized("alert.delete", "Delete") }
    static var cancel: String { localized("alert.cancel", "Cancel") }

    // MARK: Privacy

    static var showDuringScreenSharing: String { localized("privacy.screenSharing", "Show during screen sharing") }
    static var showDuringScreenSharingInfo: String {
        localized("privacy.screenSharing.info", "When off, Pasto’s windows are left out of shared screens, screenshots and recordings.")
    }
    static var generateLinkPreviews: String { localized("privacy.linkPreviews", "Generate link previews") }
    static var generateLinkPreviewsInfo: String {
        localized("privacy.linkPreviews.info", "Pasto visits the links you copy to show their title and image.")
    }
    static var ignoreConfidentialContent: String {
        localized("privacy.ignoreConfidential", "Ignore confidential content")
    }
    static var ignoreConfidentialContentInfo: String {
        localized("privacy.ignoreConfidential.info", "Passwords and other data that apps mark as secret are not saved.")
    }
    static var ignoreTransientContent: String { localized("privacy.ignoreTransient", "Ignore transient content") }
    static var ignoreTransientContentInfo: String {
        localized("privacy.ignoreTransient.info", "Content that apps put on the clipboard on their own is not saved.")
    }
    static var ignoreApplicationsTitle: String { localized("privacy.ignoreApps.title", "Ignore applications") }
    static var ignoreApplicationsInfo: String {
        localized("privacy.ignoreApps.info", "Nothing you copy in these applications is saved.")
    }
    static var noApplications: String { localized("privacy.ignoreApps.empty", "No applications") }
    static var removeAllData: String { localized("privacy.removeAll", "Remove all data") }
    static var removeAllDataInfo: String {
        localized(
            "privacy.removeAll.info",
            "The history, pinboards, what suggestions learnt, the search index and every setting. Pasto quits afterwards."
        )
    }
    static var removeAllDataButton: String { localized("privacy.removeAll.button", "Remove…") }
    static var removeAllDataTitle: String { localized("alert.removeAll.title", "Remove all of Pasto’s data and quit?") }
    static var removeAllDataMessage: String {
        localized(
            "alert.removeAll.message",
            "Pasto’s folders go to the Trash, so the history can be recovered until you empty it. Settings and the search index are erased. The permissions you granted stay in System Settings."
        )
    }
    static var removeAllDataConfirm: String { localized("alert.removeAll.confirm", "Remove and Quit") }
    static var addApplication: String { localized("privacy.ignoreApps.add", "Add application") }
    static var removeApplication: String { localized("privacy.ignoreApps.remove", "Remove") }
    static var choose: String { localized("privacy.ignoreApps.choose", "Choose") }

    // MARK: Shortcuts

    static var activatePasto: String { localized("shortcuts.activate", "Open Pasto") }
    static var activatePasteStack: String { localized("shortcuts.pasteStack", "Open Stack") }
    static var showNextPinboard: String { localized("shortcuts.nextPinboard", "Show next pinboard") }
    static var showPreviousPinboard: String { localized("shortcuts.previousPinboard", "Show previous pinboard") }
    static var quickPaste: String { localized("shortcuts.quickPaste", "Quick paste") }
    static var plainTextMode: String { localized("shortcuts.plainText", "Plain text mode") }
    static var resetShortcuts: String { localized("shortcuts.reset", "Reset Shortcuts to Default…") }
    static var resetShortcutsConfirmation: String {
        localized("shortcuts.reset.confirmation", "Reset every shortcut to its default?")
    }
    static var reset: String { localized("shortcuts.reset.confirm", "Reset") }
    static var recording: String { localized("shortcuts.recorder.recording", "Recording…") }
    static var noShortcut: String { localized("shortcuts.recorder.none", "None") }
    static var clearShortcut: String { localized("shortcuts.recorder.clear", "Clear shortcut") }
    static var spaceKey: String { localized("shortcuts.key.space", "Space") }
    /// The Paste Stack's fixed shortcut, as a conflict names it.
    static var pasteStackPasteAll: String { localized("shortcuts.pasteStackPasteAll", "Paste All") }
    static var shortcutConflictTitle: String {
        localized("shortcuts.conflict.title", "This shortcut can’t be used")
    }
    static var ok: String { localized("alert.ok", "OK") }

    static func message(for conflict: ShortcutConflict) -> String {
        switch conflict {
        case .usedByShortcut(let name):
            String(localized: "shortcuts.conflict.shortcut", defaultValue: "It’s already the shortcut for “\(name)”.", bundle: .module)
        case .usedBySystem:
            localized("shortcuts.conflict.system", "macOS already uses it for one of its keyboard shortcuts.")
        case .usedByMenuItem(let title):
            String(localized: "shortcuts.conflict.menu", defaultValue: "It’s already the shortcut for the menu command “\(title)”.", bundle: .module)
        }
    }
    static var commandKey: String { localized("shortcuts.key.command", "Command") }
    static var shiftKey: String { localized("shortcuts.key.shift", "Shift") }
    static var controlKey: String { localized("shortcuts.key.control", "Control") }
    static var optionKey: String { localized("shortcuts.key.option", "Option") }

    // MARK: Intelligence

    static var suggestionsSectionTitle: String { localized("intelligence.suggestions.title", "Suggestions") }
    static var intelligentClipboard: String { localized("intelligence.picks", "Intelligent clipboard") }
    static var intelligentClipboardInfo: String {
        localized("intelligence.picks.info", "Suggests the clips that fit what you are about to paste into.")
    }
    static var requiresAppleIntelligence: String {
        localized("intelligence.picks.requirement", "Requires Apple Intelligence")
    }
    static var allowScreenAccess: String {
        localized("intelligence.picks.allowScreenAccess", "Allow Screen Access")
    }

    // MARK: Storage summary

    /// "1,204 items".
    static func itemCount(_ count: Int) -> String {
        String(localized: "history.itemCount", defaultValue: "\(count) items", bundle: .module)
    }

    /// "You have 1,204 items (38 MB)".
    static func storageSummary(items: String, size: String) -> String {
        String(localized: "history.storageSummary", defaultValue: "You have \(items) (\(size))", bundle: .module)
    }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
