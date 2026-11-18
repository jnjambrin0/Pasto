import AppKit
import PastoCoreUI

/// The header of a preview while reading: a close button, the item's title — editable in
/// place — and the Pin, Share and Edit actions. Where the item came from and when goes in each
/// content's footer, not here.
final class PreviewHeader: NSView {
    var onClose: (() -> Void)?
    /// Called with the text of the title field when its edit ends.
    var onRename: ((String) -> Void)?
    /// Pin and Share pass the button, the anchor of what they open.
    var onPin: ((NSView) -> Void)?
    var onShare: ((NSView) -> Void)?
    var onEdit: (() -> Void)?

    private let titleField = PreviewTitleField()
    /// Pin and Share show only their symbol, with their name as a tooltip; Pin, which opens a
    /// menu, adds an arrow.
    private let pinButton = PreviewButton(
        symbolName: PinSymbol.unpinned,
        accessibilityLabel: PreviewStrings.pin,
        showsPullDownArrow: true
    )
    private let shareButton = PreviewButton(symbolName: "square.and.arrow.up", accessibilityLabel: PreviewStrings.share)
    private let editButton = PreviewButton(title: PreviewStrings.edit)

    private enum PinSymbol {
        static let unpinned = "circle.dashed"
        static let pinned = "circle.fill"
    }

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false

        // The symbol at the size the system gives it, with no configuration of its own.
        let closeButton = NSButton(
            image: NSImage(systemSymbolName: "xmark.circle.fill", accessibilityDescription: PreviewStrings.close) ?? NSImage(),
            target: self,
            action: #selector(close)
        )
        closeButton.isBordered = false
        closeButton.contentTintColor = ItemPresentation.primaryTextColor
        closeButton.alphaValue = PreviewMetrics.closeButtonOpacity
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        closeButton.setContentHuggingPriority(.required, for: .horizontal)

        pinButton.toolTip = PreviewStrings.pin
        shareButton.toolTip = PreviewStrings.share

        let actions = NSStackView(views: [pinButton, shareButton, editButton])
        actions.spacing = PreviewMetrics.actionSpacing
        actions.translatesAutoresizingMaskIntoConstraints = false

        [closeButton, titleField, actions].forEach(addSubview)
        NSLayoutConstraint.activate([
            closeButton.leadingAnchor.constraint(equalTo: leadingAnchor, constant: PreviewMetrics.closeButtonLeading),
            closeButton.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.leadingAnchor.constraint(equalTo: closeButton.trailingAnchor, constant: PreviewMetrics.titleLeading),
            titleField.centerYAnchor.constraint(equalTo: centerYAnchor),
            titleField.trailingAnchor.constraint(lessThanOrEqualTo: actions.leadingAnchor, constant: -PreviewMetrics.actionSpacing),
            actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -PreviewMetrics.headerTrailing),
            actions.centerYAnchor.constraint(equalTo: centerYAnchor),
        ])

        titleField.onCommit = { [weak self] text in self?.onRename?(text) }
        pinButton.onClick = { [weak self] button in self?.onPin?(button) }
        shareButton.onClick = { [weak self] button in self?.onShare?(button) }
        editButton.onClick = { [weak self] _ in self?.onEdit?() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PreviewHeader is created in code")
    }

    /// - Parameters:
    ///   - placeholder: What the title reads while the item has none: the name of its type.
    ///   - pinboardColor: The colour of the pinboard the item is on, `nil` when it is on none.
    func configure(title: String?, placeholder: String, pinboardColor: NSColor?, canShare: Bool, canEdit: Bool) {
        titleField.setTitle(title, placeholder: placeholder)
        pinButton.setSymbol(pinboardColor == nil ? PinSymbol.unpinned : PinSymbol.pinned)
        pinButton.symbolTint = pinboardColor
        shareButton.isEnabled = canShare
        editButton.isHidden = !canEdit
    }

    func beginTitleEditing() {
        titleField.beginEditing()
    }

    func cancelTitleEditing() {
        titleField.cancelEditing()
    }

    @objc private func close() {
        onClose?()
    }
}
