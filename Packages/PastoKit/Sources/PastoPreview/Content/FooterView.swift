import AppKit
import PastoCoreUI

/// The strip under a preview's content, which each kind of content fills with its own details.
/// It has no fill of its own and is as tall as what it holds plus its margins.
final class FooterView: NSView {
    private let container = NSView(frame: .zero)

    init() {
        super.init(frame: .zero)
        translatesAutoresizingMaskIntoConstraints = false
        container.translatesAutoresizingMaskIntoConstraints = false
        addSubview(container)

        let insets = PreviewMetrics.footerInsets
        NSLayoutConstraint.activate([
            container.topAnchor.constraint(equalTo: topAnchor, constant: insets.top),
            container.leadingAnchor.constraint(equalTo: leadingAnchor, constant: insets.left),
            container.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -insets.bottom),
            container.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -insets.right),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FooterView is created in code")
    }

    /// Replaces whatever the footer showed.
    func setContent(_ content: NSView) {
        container.subviews.forEach { $0.removeFromSuperview() }
        content.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
        ])
        layoutSubtreeIfNeeded()
    }

    /// A caption at the start and, optionally, a button at the far end: the footer of images,
    /// links and files.
    ///
    /// - Parameter wraps: Whether a caption too long for one line continues on the next
    ///   instead of being cut.
    func setCaption(_ caption: String, wraps: Bool = false, button: PreviewButton? = nil) {
        let label = wraps ? NSTextField(wrappingLabelWithString: caption) : NSTextField(labelWithString: caption)
        label.isSelectable = false
        label.lineBreakMode = wraps ? .byWordWrapping : .byTruncatingTail
        label.font = .preferredFont(forTextStyle: .body)
        label.textColor = ItemPresentation.secondaryTextColor
        // The caption gives way to the button, never the other way round.
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let spacer = NSView(frame: .zero)
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        spacer.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContent(NSStackView(views: [label, spacer] + [button].compactMap(\.self)))
    }
}
