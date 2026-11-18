import Foundation

/// The permission windows' user-facing strings. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
///
/// The System Settings names they quote are macOS 27's, in both languages: Privacy & Security ›
/// Device Control and Data Access (formerly Accessibility), Screen & System Audio Recording, and
/// Paste from Other Apps, whose choices are Ask, Deny and Allow (the string tables of the
/// SecurityPrivacyExtension settings extension and of TCC).
enum PermissionStrings {
    // MARK: Shared

    static var openSystemSettings: String { localized("action.openSystemSettings", "Open System Settings") }
    static var allowAccess: String { localized("action.allowAccess", "Allow Access") }
    static var accessGranted: String { localized("state.granted", "Access granted") }

    // MARK: Paste to other apps

    static func pasteToOtherAppsTitle(_ applicationName: String) -> String {
        String(localized: "pasteToOtherApps.title", defaultValue: "Paste straight into \(applicationName)?", bundle: .module)
    }
    static var currentApplication: String { localized("pasteToOtherApps.currentApp", "the app you’re using") }
    static var pasteToOtherAppsDescription: String {
        localized(
            "pasteToOtherApps.description",
            "Pasto can press ⌘V for you, so the item you choose lands where you were typing. macOS asks for Device Control and Data Access before an app may do that."
        )
    }
    static var allowAccessibilityAccess: String { localized("pasteToOtherApps.allow", "Allow Access") }
    static var copyToClipboard: String { localized("pasteToOtherApps.copy", "Not Now, Just Copy It") }
    static var doNotAskAgain: String { localized("pasteToOtherApps.doNotAskAgain", "Don’t ask again") }

    // MARK: Accessibility

    static var accessibilityTitle: String { localized("accessibility.title", "Paste Into Any App") }
    static var accessibilitySubtitle: String {
        localized(
            "accessibility.subtitle",
            "Once Pasto is allowed under Device Control and Data Access, choosing an item pastes it into the app you were using. Without it, Pasto can only copy the item for you to paste."
        )
    }

    // MARK: Pasteboard

    static var pasteboardTitle: String { localized("pasteboard.title", "Let Pasto See What You Copy") }
    static var pasteboardSubtitle: String {
        localized(
            "pasteboard.subtitle",
            "Pasto keeps your history by reading the clipboard each time you copy. In System Settings › Privacy & Security › Paste from Other Apps, choose Allow for Pasto so macOS doesn’t ask every time."
        )
    }

    // MARK: Screen recording

    static var screenRecordingTitle: String { localized("screenRecording.title", "Suggestions While You Paste") }
    static var screenRecordingSubtitle: String {
        localized(
            "screenRecording.subtitle",
            "With Screen & System Audio Recording access, Pasto looks at the window you are about to paste into and suggests the items that fit it."
        )
    }

    /// Under the button once the system has asked: what System Settings will do, and the way
    /// out when Pasto's switch there is on but does not take.
    static var quitAndReopenHint: String {
        localized(
            "screenRecording.quitAndReopen",
            "Turn Pasto on in the list. When macOS offers “Quit & Reopen”, choose it: Pasto opens again and finishes here. If Pasto is already on, turn it off and on again."
        )
    }

    // MARK: Screen capture check

    static var continueAction: String { localized("action.continue", "Continue") }
    static var checking: String { localized("action.checking", "Checking…") }
    static var screenCaptureCheckTitle: String { localized("screenCaptureCheck.title", "One More Step") }
    static var screenCaptureCheckSubtitle: String {
        localized(
            "screenCaptureCheck.subtitle",
            "Screen recording is on. macOS asks once more whether Pasto may access your screen directly — and again about once a month: choose Allow."
        )
    }
    static var screenCaptureCheckFailed: String {
        localized("screenCaptureCheck.failed", "macOS didn’t allow it. Choose Continue again, then Allow.")
    }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
