import AppKit
import PastoCore

/// A view that shows the content of one item inside a preview. What else it can do, it says by
/// adopting the protocols below.
protocol ItemContentView: NSView {
    /// Shows the item again after it changed in the store. Its kind of content is the same:
    /// when that changes the preview builds another view.
    func update(with item: Item)
}

/// Content with details to show under it.
protocol FooterProviding {
    var footer: FooterView { get }
}

/// Content that knows how large it wants to open; the rest gets a fraction of the screen.
protocol PreferredSizeProviding {
    /// - Parameter screenSize: The frame of the main screen, `nil` when there is none.
    func preferredContentSize(screenSize: CGSize?) -> CGSize
}

/// Content the user can change in place.
protocol EditableContent: AnyObject {
    /// Told whether there is something to save, when editing starts and on every change.
    var onCanCommitChange: ((Bool) -> Void)? { get set }
    /// Controls of its own for the middle of the editing header.
    var editingToolbar: NSView? { get }

    func beginEditing()
    /// Drops the changes. Nothing asks the user first.
    func cancelEditing()
    /// Saves the changes to the store.
    func commitEditing()
    /// Gives keyboard focus to what is being edited, once the view is in its window.
    func focusEditor()
}

extension EditableContent {
    func focusEditor() {}
}

/// Which content view shows an item.
nonisolated enum ItemContentKind: Equatable {
    case text
    case link(URL)
    case image
    case color
    case files
    case unknown

    init(item: Item) {
        switch item.type {
        case .text: self = .text
        case .image: self = .image
        case .color: self = .color
        case .files: self = .files
        case .unknown: self = .unknown
        case .link:
            // A link whose address could not be rebuilt is stored with a text preview, and is
            // shown as the text it is.
            if case .link(let preview) = item.preview { self = .link(preview.url) } else { self = .text }
        }
    }

    /// Files and content of no known kind cannot be edited.
    var isEditable: Bool {
        switch self {
        case .text, .link, .image, .color: true
        case .files, .unknown: false
        }
    }
}

enum ItemContentFactory {
    /// - Parameter dismiss: Closes the preview the view is in.
    static func makeView(
        for item: Item,
        environment: PreviewEnvironment,
        dismiss: @escaping () -> Void
    ) -> any ItemContentView {
        switch ItemContentKind(item: item) {
        case .text: TextContentView(item: item, environment: environment)
        case .link(let url): LinkContentView(item: item, url: url, environment: environment)
        case .image: ImageContentView(item: item, environment: environment)
        case .color: ColorContentView(item: item, environment: environment)
        case .files: FilesContentView(item: item, environment: environment, dismiss: dismiss)
        case .unknown: UnknownContentView()
        }
    }
}

extension NSView {
    /// Whether the view is drawn in a dark appearance.
    var isInDarkMode: Bool {
        effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }
}
