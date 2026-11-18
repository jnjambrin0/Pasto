import Foundation

/// The user-facing strings of the preview, the editors and the New Text Item window. The English
/// and Spanish texts live in `Resources/Localizable.xcstrings`; the English one is repeated here
/// as the fallback for a build that does not compile the catalog.
enum PreviewStrings {
    // MARK: Headers

    static var close: String { localized("preview.action.close", "Close") }
    static var previewWindowTitle: String { localized("window.preview", "Preview") }
    static var editorWindowTitle: String { localized("window.editor", "Edit Item") }
    static var newTextItemWindowTitle: String { localized("window.newTextItem", "New Text Item") }
    static var pin: String { localized("preview.action.pin", "Pin") }
    static var share: String { localized("preview.action.share", "Share") }
    static var edit: String { localized("preview.action.edit", "Edit") }
    static var cancel: String { localized("editor.action.cancel", "Cancel") }
    static var save: String { localized("editor.action.save", "Save") }
    static var discardChanges: String { localized("editor.tooltip.discardChanges", "Discard changes") }
    static var saveChanges: String { localized("editor.tooltip.saveChanges", "Save changes") }

    // MARK: Text

    static var bold: String { localized("editor.text.bold", "Bold") }
    static var italic: String { localized("editor.text.italic", "Italic") }
    static var underline: String { localized("editor.text.underline", "Underline") }
    static var strikethrough: String { localized("editor.text.strikethrough", "Strikethrough") }
    static var writingTools: String { localized("editor.text.writingTools", "Writing Tools") }

    static func characterCount(_ count: Int) -> String { counted("statistics.characters", count) }
    static func wordCount(_ count: Int) -> String { counted("statistics.words", count) }
    static func lineCount(_ count: Int) -> String { counted("statistics.lines", count) }

    // MARK: Link

    static func openIn(_ application: String) -> String {
        String(localized: "link.openIn", defaultValue: "Open in \(application)", bundle: .module)
    }
    static var browser: String { localized("link.browser", "Browser") }

    // MARK: Image

    static var rotateLeft: String { localized("editor.image.rotateLeft", "Rotate Left") }
    static var rotateRight: String { localized("editor.image.rotateRight", "Rotate Right") }

    // MARK: Files

    static var multipleFiles: String { localized("files.multiple", "Multiple files") }
    static var showInFinder: String { localized("files.showInFinder", "Show in Finder") }

    // MARK: Unknown

    static var unavailableTitle: String { localized("unavailable.title", "No preview for this item") }
    static var unavailableMessage: String {
        localized("unavailable.message", "Its content is saved all the same, and you can still paste it.")
    }

    // MARK: New Text Item

    static var create: String { localized("newItem.action.create", "Create") }
    static var createTextItem: String { localized("newItem.tooltip.create", "Create text item") }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }

    /// A string whose wording depends on a number, which the catalog varies by plural category.
    private static func counted(_ key: String, _ count: Int) -> String {
        String(format: Bundle.module.localizedString(forKey: key, value: nil, table: nil), locale: .autoupdatingCurrent, count)
    }
}
