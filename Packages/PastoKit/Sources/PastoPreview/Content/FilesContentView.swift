import AppKit
import PastoCore
import Quartz

/// The preview of a files item: Quick Look for a single file, the system's "several documents"
/// icon for any other number, and under it the path, the size and a button to show the files
/// in the Finder. Files are not edited.
final class FilesContentView: NSView, ItemContentView, FooterProviding, PreferredSizeProviding {
    let footer = FooterView()

    private let environment: PreviewEnvironment
    private let itemID: ItemID
    private let dismiss: () -> Void
    private let fileItem: FilePreviewItem?
    private var quickLookView: QLPreviewView?
    private var documentsIcon: NSImageView?

    init(item: Item, environment: PreviewEnvironment, dismiss: @escaping () -> Void) {
        self.environment = environment
        itemID = item.id
        self.dismiss = dismiss

        let files: FilesPreview? = if case .files(let preview) = item.preview { preview } else { nil }
        let paths = files?.paths ?? []
        // The file is previewed where it is: nothing is copied anywhere.
        fileItem = paths.count == 1 ? FilePreviewItem(path: paths[0], title: item.title) : nil
        super.init(frame: .zero)

        if fileItem != nil, let quickLookView = UnfocusableQuickLookView(frame: .zero, style: .normal) {
            quickLookView.autoresizingMask = [.width, .height]
            addSubview(quickLookView)
            self.quickLookView = quickLookView
        } else {
            let icon = NSImageView(frame: .zero)
            icon.image = NSImage(named: NSImage.multipleDocumentsName)
            icon.imageScaling = .scaleProportionallyDown
            // The caption under it names the files; the icon would read as "image".
            icon.setAccessibilityElement(false)
            addSubview(icon)
            documentsIcon = icon
        }

        let button = PreviewButton(title: PreviewStrings.showInFinder)
        button.onClick = { [weak self] _ in self?.showInFinder() }
        footer.setCaption(
            FilesCaption.text(
                paths: paths, totalByteCount: files?.totalByteCount, multipleFilesTitle: PreviewStrings.multipleFiles
            ),
            wraps: true,
            button: button
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FilesContentView is created in code")
    }

    /// The files of an item do not change: only its title could, and Quick Look has it already.
    func update(with item: Item) {}

    override func layout() {
        super.layout()
        let side = PreviewMetrics.filesIconSide
        documentsIcon?.frame = NSRect(
            x: ((bounds.width - side) / 2).rounded(), y: ((bounds.height - side) / 2).rounded(), width: side, height: side
        )
    }

    /// Quick Look starts loading once, when the view is first in a window.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard window != nil, let quickLookView, quickLookView.previewItem == nil else { return }
        quickLookView.previewItem = fileItem
    }

    func preferredContentSize(screenSize: CGSize?) -> CGSize {
        PreviewSize.largeContentSize(screenSize: screenSize)
    }

    /// Selects every file of the item in the Finder — from its pasteboard data, not from the
    /// stored preview — and closes the preview.
    private func showInFinder() {
        let urls = (environment.reader.pasteboardItems(for: itemID) ?? [])
            .compactMap(\.filePath)
            .map { URL(fileURLWithPath: $0) }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
        NSApp.deactivate()
        environment.handlers.closePanel()
        dismiss()
    }
}

/// A Quick Look view that never takes keyboard focus: with the preview open, keys still belong
/// to the strip of cards.
private final class UnfocusableQuickLookView: QLPreviewView {
    override var acceptsFirstResponder: Bool { false }
}

/// Quick Look reads it from its own threads, hence not bound to the main actor.
private nonisolated final class FilePreviewItem: NSObject, QLPreviewItem {
    let previewItemURL: URL!
    let previewItemTitle: String!

    init(path: String, title: String?) {
        previewItemURL = URL(fileURLWithPath: path)
        previewItemTitle = title
    }
}
