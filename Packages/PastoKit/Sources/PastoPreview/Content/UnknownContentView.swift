import AppKit
import PastoCore
import PastoCoreUI

/// What a preview shows for content of no known kind: a warning sign and two lines saying the
/// content is kept and can be pasted. It has no footer, cannot be edited and, unlike the other
/// content views, gets no border.
final class UnknownContentView: NSView, ItemContentView {
    init() {
        super.init(frame: .zero)

        let symbol = NSImageView(frame: .zero)
        symbol.image = NSImage(systemSymbolName: "exclamationmark.triangle", accessibilityDescription: nil)
        symbol.imageScaling = .scaleProportionallyUpOrDown
        symbol.contentTintColor = ItemPresentation.secondaryTextColor
        // The two lines say it all; the sign would read as "image".
        symbol.setAccessibilityElement(false)

        let title = NSTextField(labelWithString: PreviewStrings.unavailableTitle)
        title.font = .systemFont(ofSize: NSFont.preferredFont(forTextStyle: .title2).pointSize, weight: .medium)
        title.textColor = ItemPresentation.primaryTextColor
        title.alignment = .center

        let message = NSTextField(wrappingLabelWithString: PreviewStrings.unavailableMessage)
        message.isSelectable = false
        message.font = .preferredFont(forTextStyle: .body)
        message.textColor = ItemPresentation.secondaryTextColor
        message.alignment = .center
        message.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let texts = NSStackView(views: [title, message])
        texts.orientation = .vertical
        texts.spacing = PreviewMetrics.unavailableTextSpacing

        let stack = NSStackView(views: [symbol, texts])
        stack.orientation = .vertical
        stack.spacing = PreviewMetrics.unavailableSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        let margin = PreviewMetrics.unavailableSideMargin
        let side = PreviewMetrics.unavailableSymbolSide
        NSLayoutConstraint.activate([
            symbol.widthAnchor.constraint(equalToConstant: side),
            symbol.heightAnchor.constraint(equalToConstant: side),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: margin),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -margin),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("UnknownContentView is created in code")
    }

    func update(with item: Item) {}
}
