import Foundation

/// The user-facing strings of what can be done with an item: its context menu and the alerts.
/// The English and Spanish texts live in `Resources/Localizable.xcstrings`; the English one is
/// repeated here as the fallback for a build that does not compile the catalog.
enum ItemActionStrings {
    // MARK: Context menu

    static var open: String { localized("menu.item.open", "Open") }
    static func openWith(_ application: String) -> String {
        String(localized: "menu.item.openWith", defaultValue: "Open with \(application)", bundle: .module)
    }
    static var revealInFinder: String { localized("menu.item.revealInFinder", "Reveal in Finder") }
    static func showIn(_ list: String) -> String {
        String(localized: "menu.item.showIn", defaultValue: "Show in \(list)", bundle: .module)
    }
    static func pasteTo(_ application: String) -> String {
        String(localized: "menu.item.pasteTo", defaultValue: "Paste to \(application)", bundle: .module)
    }
    static var currentApplication: String { localized("menu.item.currentApp", "current app") }
    static var pasteAsPlainText: String { localized("menu.item.pasteAsPlainText", "Paste as Plain Text") }
    static var copy: String { localized("menu.item.copy", "Copy") }
    static var createStack: String { localized("menu.item.createStack", "Create Stack") }
    static var edit: String { localized("menu.item.edit", "Edit") }
    static var rename: String { localized("menu.item.rename", "Rename") }
    static var delete: String { localized("menu.item.delete", "Delete") }
    static var pin: String { localized("menu.item.pin", "Pin") }
    static var preview: String { localized("menu.item.preview", "Preview") }
    static var share: String { localized("menu.item.share", "Share") }

    // MARK: Pin submenu

    static var createPinboard: String { localized("menu.pin.createPinboard", "Create Pinboard…") }
    static var unpin: String { localized("menu.pin.unpin", "Unpin") }

    // MARK: Alerts

    static func deleteItemsTitle(_ count: Int) -> String {
        String(localized: "alert.deleteItems.title", defaultValue: "Delete \(count) items?", bundle: .module)
    }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
