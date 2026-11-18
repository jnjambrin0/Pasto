import Foundation
import PastoInput

/// The user-facing strings of onboarding, the notice cards and the About window. The English
/// and Spanish texts live in `Resources/Localizable.xcstrings`; the English one is repeated
/// here as the fallback for a build that does not compile the catalog.
nonisolated enum OnboardingStrings {
    // MARK: Introduction

    static var welcomeWindowTitle: String { localized("window.title", "Welcome to Pasto") }

    static var introTitle: String { localized("intro.title", "Everything You Copy, Ready to Paste Again") }
    static var introSubtitle: String {
        localized(
            "intro.subtitle",
            "Pasto remembers the text, links, images and files you copy, so you can find any of them later and paste it wherever you are working."
        )
    }
    static var getStarted: String { localized("intro.action", "Get Started") }

    // MARK: Shared by the steps

    static var notNow: String { localized("step.notNow", "Not Now") }
    static var openSystemSettings: String { localized("step.openSystemSettings", "Open System Settings") }
    /// What VoiceOver says a state row's state is.
    static var stateDone: String { localized("state.done", "Done") }
    static var statePending: String { localized("state.pending", "Pending") }
    static var stateWorking: String { localized("state.working", "In progress") }

    // MARK: Permission steps (the names are System Settings' in macOS 27, as in PermissionStrings)

    static var accessibilitySettingName: String { localized("directPaste.settingName", "Device Control and Data Access") }
    static var accessibilityAllowed: String {
        localized("directPaste.allowed", "Allowed. Choosing an item pastes it where you were.")
    }
    static var accessibilityNotAllowed: String { localized("directPaste.notAllowed", "Not allowed yet.") }
    static var accessibilityHint: String { localized("directPaste.hint", "In the list, turn Pasto on, then come back here.") }
    static var pasteboardSettingName: String { localized("pasteboard.settingName", "Paste from Other Apps") }
    static var pasteboardAllowed: String { localized("pasteboard.allowed", "Allow. Pasto saves everything you copy.") }
    static var pasteboardAsks: String {
        localized("pasteboard.asks", "Ask. macOS would ask every time you copy: choose Allow.")
    }
    static var pasteboardDenied: String {
        localized("pasteboard.denied", "Deny. Pasto can’t save what you copy: choose Allow.")
    }
    static var pasteboardUndetermined: String { localized("pasteboard.undetermined", "Not chosen yet: choose Allow.") }

    // MARK: Suggestions step

    static var suggestionsTitle: String { localized("suggestions.title", "Smart Suggestions") }
    static var suggestionsSubtitle: String {
        localized(
            "suggestions.subtitle",
            "When you open Pasto, it can put first the items that suit the app you’re pasting into. It all happens on this Mac, with Apple Intelligence: Pasto looks at that window for a moment and keeps nothing of it."
        )
    }
    static var suggestionsSwitchTitle: String { localized("suggestions.switch.title", "Suggest items as I paste") }
    static var suggestionsSwitchSubtitle: String {
        localized("suggestions.switch.subtitle", "You can change it at any time in Settings › Intelligence.")
    }
    static var appleIntelligenceTitle: String { localized("suggestions.appleIntelligence.title", "Apple Intelligence") }
    static var appleIntelligenceOff: String {
        localized("suggestions.appleIntelligence.off", "Off. Turn it on in System Settings › Apple Intelligence & Siri.")
    }
    static var screenRecordingSettingName: String {
        localized("suggestions.screenRecording.title", "Screen & System Audio Recording")
    }
    static var screenRecordingAllowed: String { localized("suggestions.screenRecording.allowed", "Allowed.") }
    static var screenRecordingNotAllowed: String { localized("suggestions.screenRecording.notAllowed", "Not allowed yet.") }
    static var screenRecordingWaiting: String {
        localized("suggestions.screenRecording.waiting", "In System Settings, turn Pasto on in the list.")
    }
    static var allowScreenRecording: String { localized("suggestions.allow", "Allow Screen Recording") }
    static var quitAndReopenHint: String {
        localized(
            "suggestions.quitAndReopen",
            "macOS then offers to quit and reopen Pasto: choose “Quit & Reopen”, and Pasto comes back to this step."
        )
    }
    static var confirmationTitle: String { localized("suggestions.confirmation.title", "macOS confirmation") }
    /// What macOS will ask, and what to answer; in the row, where it fits beside the third row.
    static var confirmationPending: String {
        localized(
            "suggestions.confirmation.pending",
            "When you check, macOS asks whether Pasto may access the screen directly: choose Allow. It asks again about once a month."
        )
    }
    static var confirmationDone: String { localized("suggestions.confirmation.done", "Confirmed.") }
    static var confirmationFailed: String {
        localized("suggestions.confirmation.failed", "Not confirmed: check again and choose Allow.")
    }
    static var runCheck: String { localized("suggestions.check", "Check Now") }
    static var checking: String { localized("suggestions.checking", "Checking…") }

    // MARK: Quick Start

    static var quickStartTitle: String { localized("setup.title", "Quick Start") }
    static var quickStartSubtitle: String {
        localized("setup.subtitle", "A few choices to begin with. You can change them at any time in Settings.")
    }
    static var openAtLoginTitle: String { localized("setup.openAtLogin.title", "Open at login") }
    static var openAtLoginSubtitle: String {
        localized("setup.openAtLogin.subtitle", "Pasto starts with your Mac and stays out of the way.")
    }
    static var shortcutTitle: String { localized("setup.shortcut.title", "Activation shortcut") }
    static var shortcutSubtitle: String { localized("setup.shortcut.subtitle", "Opens and closes Pasto from any app.") }
    /// Under the activation shortcut, when launch took ⌃⇧⌘V because another app has ⇧⌘V.
    static func shortcutTakenNote(_ preferred: String) -> String {
        String(
            localized: "setup.shortcut.takenNote",
            defaultValue: "Another app already uses \(preferred). You can choose a different shortcut here.",
            bundle: .module
        )
    }
    /// Under the activation shortcut, when launch found both ⇧⌘V and ⌃⇧⌘V in use.
    static func shortcutsTakenNote(_ preferred: String, _ alternate: String) -> String {
        String(
            localized: "setup.shortcut.bothTakenNote",
            defaultValue: "Other apps already use \(preferred) and \(alternate). Choose a shortcut here to open Pasto.",
            bundle: .module
        )
    }
    static var recordingShortcut: String { localized("setup.shortcut.recording", "Recording…") }
    static var noShortcut: String { localized("setup.shortcut.none", "None") }
    static var clearShortcut: String { localized("setup.shortcut.clear", "Clear shortcut") }
    static var spaceKey: String { localized("setup.shortcut.space", "Space") }
    static var shortcutConflictTitle: String { localized("setup.shortcut.conflict.title", "This shortcut can’t be used") }
    static var ok: String { localized("alert.ok", "OK") }

    // The names of Pasto's other shortcuts, as a conflict reports them: those of Settings › Shortcuts.
    static var pasteStackShortcutName: String { localized("setup.shortcut.name.pasteStack", "Open Stack") }
    static var nextPinboardShortcutName: String { localized("setup.shortcut.name.nextPinboard", "Show next pinboard") }
    static var previousPinboardShortcutName: String {
        localized("setup.shortcut.name.previousPinboard", "Show previous pinboard")
    }
    static var pasteStackPasteAllName: String { localized("setup.shortcut.name.pasteAll", "Paste All") }

    static func message(for conflict: ShortcutConflict) -> String {
        switch conflict {
        case .usedByShortcut(let name):
            String(localized: "setup.shortcut.conflict.shortcut", defaultValue: "It’s already the shortcut for “\(name)”.", bundle: .module)
        case .usedBySystem:
            localized("setup.shortcut.conflict.system", "macOS already uses it for one of its keyboard shortcuts.")
        case .usedByMenuItem(let title):
            String(localized: "setup.shortcut.conflict.menu", defaultValue: "It’s already the shortcut for the menu command “\(title)”.", bundle: .module)
        }
    }
    static var historyTitle: String { localized("setup.history.title", "Clipboard history") }
    static var historySubtitle: String { localized("setup.history.subtitle", "How long Pasto keeps what you copy.") }
    static var unlimited: String { localized("setup.history.unlimited", "Unlimited") }
    static var unlimitedWarning: String {
        localized("setup.history.unlimitedWarning", "A history without a limit can take up a lot of disk space over time.")
    }
    static var continueAction: String { localized("setup.action", "Continue") }
    /// The last step's button, which closes the welcome and opens the panel.
    static var finishAction: String { localized("setup.finish", "Start Using Pasto") }
    static var reduceHistoryTitle: String {
        localized("alert.reduceHistory.title", "Some items are older than the new limit. Delete them and apply the limit?")
    }
    static var reduceHistoryMessage: String {
        localized("alert.reduceHistory.message", "Pinned items and pinboards are kept. This can’t be undone.")
    }
    static var delete: String { localized("alert.delete", "Delete") }
    static var cancel: String { localized("alert.cancel", "Cancel") }

    // MARK: Notice cards

    static var openAtLoginNoticeTitle: String { localized("notice.openAtLogin.title", "Open at Login") }
    static var openAtLoginNoticeDescription: String {
        localized("notice.openAtLogin.description", "Start Pasto with your Mac so nothing you copy is missed.")
    }
    static var directPasteNoticeTitle: String { localized("notice.directPaste.title", "Paste Directly") }
    static var directPasteNoticeDescription: String {
        localized("notice.directPaste.description", "Have the item you choose pasted into the app you are using.")
    }
    static var pasteboardAccessNoticeTitle: String { localized("notice.pasteboardAccess.title", "Pasto Can’t See What You Copy") }
    static var pasteboardAccessNoticeDescription: String {
        localized("notice.pasteboardAccess.description", "Nothing you copy is saved until you allow it.")
    }
    static var otherClipboardManagersNoticeTitle: String {
        localized("notice.otherClipboardManagers.title", "Another Clipboard App")
    }
    /// - Parameter names: The other clipboard managers that are open, as a list ("Maccy and Flycut").
    static func otherClipboardManagersNoticeDescription(_ names: String) -> String {
        String(
            localized: "notice.otherClipboardManagers.description",
            defaultValue: "Also running: \(names). When two apps share a shortcut, only one of them responds.",
            bundle: .module
        )
    }
    static var shortcutsTakenNoticeTitle: String {
        localized("notice.shortcutsTaken.title", "Shortcut in Use")
    }
    /// - Parameter shortcuts: The shortcuts, as a list ("⇧⌘V and ⇧⌘C").
    static func shortcutsTakenNoticeDescription(_ shortcuts: String) -> String {
        String(
            localized: "notice.shortcutsTaken.description",
            defaultValue: "Another app or macOS also uses \(shortcuts), so it may not reach Pasto.",
            bundle: .module
        )
    }
    static var storeWriteFailureNoticeTitle: String {
        localized("notice.storeWriteFailure.title", "Pasto Can’t Save What You Copy")
    }
    static var storeWriteFailureNoticeDescription: String {
        localized("notice.storeWriteFailure.description", "Your Mac may be out of space. Pasto keeps trying and this card goes away once it can save again.")
    }
    static var storage: String { localized("notice.action.storage", "Storage…") }
    static var change: String { localized("notice.action.change", "Change…") }
    static var enable: String { localized("notice.action.enable", "Enable") }
    static var allow: String { localized("notice.action.allow", "Allow…") }
    static var gotIt: String { localized("notice.action.gotIt", "Got It") }
    static var enabled: String { localized("notice.enabled", "Enabled") }
    static var closeNotice: String { localized("notice.close", "Close") }

    // MARK: About

    static func version(_ version: String) -> String {
        String(localized: "about.version", defaultValue: "Version \(version)", bundle: .module)
    }
    static var aboutWindowTitle: String { localized("about.windowTitle", "About Pasto") }
    static var aboutCopyright: String { localized("about.copyright", "© 2026 Jaime Navas") }
    static var aboutDisclaimer: String {
        localized("about.disclaimer", "Free software, provided as is, without warranty.")
    }
    static var acknowledgements: String { localized("about.acknowledgements", "Acknowledgements") }
    static var acknowledgementsIntroduction: String {
        localized(
            "acknowledgements.introduction",
            "Pasto includes the following third-party software, distributed under these licenses."
        )
    }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
