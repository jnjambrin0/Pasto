import Foundation

/// The suggestions mode's user-facing strings. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
enum PicksStrings {
    // MARK: Strip

    static var empty: String { localized("picks.empty", "Nothing to suggest") }
    static var accessTitle: String { localized("picks.access.title", "Suggestions for where you paste") }
    static var accessSubtitle: String {
        localized(
            "picks.access.subtitle",
            "Pasto looks at the window you’re about to paste into, here on your Mac, to pick the clips that fit it. Nothing is saved or sent anywhere."
        )
    }
    static var allowAccess: String { localized("picks.access.allow", "Allow Screen Recording…") }

    // MARK: Turning off

    static var turnOffMenuItem: String { localized("picks.turnOff.menuItem", "Turn Off…") }
    static var turnOffTitle: String { localized("picks.turnOff.title", "Turn off suggestions?") }
    static var turnOffMessage: String {
        localized("picks.turnOff.message", "To get them back, open Pasto Settings › Intelligence.")
    }
    static var turnOff: String { localized("picks.turnOff.confirm", "Turn Off") }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
