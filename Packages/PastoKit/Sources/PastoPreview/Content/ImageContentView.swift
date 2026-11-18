import AppKit
import PastoCore
import PastoCoreUI

/// The preview of an image item: the full-size image — not the card's thumbnail — over a
/// checkerboard, zoomable, with its size underneath. Editing turns it a quarter at a time.
final class ImageContentView: NSView, ItemContentView, FooterProviding, PreferredSizeProviding, EditableContent {
    let footer = FooterView()
    var onCanCommitChange: ((Bool) -> Void)?
    private(set) lazy var editingToolbar: NSView? = makeToolbar()

    private let environment: PreviewEnvironment
    private let itemID: ItemID
    private let imageView = ZoomableImageView()
    private var isEditing = false
    /// Quarter turns clockwise since editing began, 0...3. Four in a row are no change.
    private var quarterTurns = 0

    init(item: Item, environment: PreviewEnvironment) {
        self.environment = environment
        itemID = item.id
        super.init(frame: .zero)

        // Always there: it shows wherever the image is transparent or does not reach.
        let checkerboard = CheckerboardView(frame: .zero)
        for view in [checkerboard, imageView] {
            view.autoresizingMask = [.width, .height]
            addSubview(view)
        }
        showStoredImage()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ImageContentView is created in code")
    }

    func update(with item: Item) {
        guard !isEditing else { return }
        showStoredImage()
    }

    /// The first image among the item's pasteboard items, at full size.
    private func showStoredImage() {
        let data = environment.reader.pasteboardItems(for: itemID)?.lazy.compactMap(\.imageData).first
        imageView.image = data.flatMap(NSImage.init(data:))
        quarterTurns = 0
        refresh()
    }

    /// The footer shows the size of the image as it is now, turns included.
    private func refresh() {
        let size = imageView.image?.size ?? .zero
        footer.setCaption("\(Int(size.width)) × \(Int(size.height))")
        if isEditing {
            onCanCommitChange?(quarterTurns != 0)
        }
    }

    // MARK: - PreferredSizeProviding

    func preferredContentSize(screenSize: CGSize?) -> CGSize {
        PreviewSize.imageContentSize(imageSize: imageView.image?.size ?? .zero, screenSize: screenSize)
    }

    // MARK: - Rotation

    private func makeToolbar() -> NSView {
        let left = PreviewButton(symbolName: "rotate.left", accessibilityLabel: PreviewStrings.rotateLeft)
        left.toolTip = PreviewStrings.rotateLeft
        left.onClick = { [weak self] _ in self?.rotate(byQuarterTurns: -1) }

        let right = PreviewButton(symbolName: "rotate.right", accessibilityLabel: PreviewStrings.rotateRight)
        right.toolTip = PreviewStrings.rotateRight
        right.onClick = { [weak self] _ in self?.rotate(byQuarterTurns: 1) }

        let toolbar = NSStackView(views: [left, right])
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        return toolbar
    }

    private func rotate(byQuarterTurns turns: Int) {
        guard isEditing, let rotated = imageView.image?.rotated(byQuarterTurns: turns) else { return }
        imageView.image = rotated
        quarterTurns = (quarterTurns + turns + 4) % 4
        refresh()
        undoManager?.registerUndo(withTarget: self) { view in
            view.rotate(byQuarterTurns: -turns)
        }
    }

    // MARK: - EditableContent

    /// Save starts enabled; whether there is a turn to save is only worked out once the image
    /// has been turned.
    func beginEditing() {
        isEditing = true
        imageView.isTextSelectionEnabled = false
        onCanCommitChange?(true)
    }

    func cancelEditing() {
        endEditing()
        showStoredImage()
    }

    func commitEditing() {
        endEditing()
        if let encoded = imageView.image?.encodedForSaving {
            environment.replaceContent(of: itemID, with: ItemContentComposer.image(encoded))
        }
        quarterTurns = 0
        refresh()
    }

    private func endEditing() {
        isEditing = false
        imageView.isTextSelectionEnabled = true
        undoManager?.removeAllActions(withTarget: self)
    }
}
