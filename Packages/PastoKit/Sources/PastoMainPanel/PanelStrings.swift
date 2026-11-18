import Foundation

/// User-facing strings of the panel outside its toolbar tabs, menus and search. The English and
/// Spanish texts live in `Resources/Localizable.xcstrings`; the English one is repeated here as
/// the fallback for a build that does not compile the catalog.
enum PanelStrings {
    // MARK: Empty lists

    static var emptyHistory: String { localized("placeholder.emptyHistory", "Nothing copied yet") }
    static var emptyPinboard: String { localized("placeholder.emptyPinboard", "No items on this pinboard") }

    // MARK: Pause indicator

    static var paused: String { localized("toolbar.pause.paused", "Pasto Paused") }

    /// "Paused until 18:30".
    static func pausedUntil(_ time: String) -> String {
        String(localized: "toolbar.pause.pausedUntil", defaultValue: "Paused until \(time)", bundle: .module)
    }

    static var pauseButton: String { localized("toolbar.pause.button", "Pause Options") }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
