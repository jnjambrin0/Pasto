import AppKit

/// A notice card: symbol, title, description, a button and a close button. Its host gives it a
/// frame of `NoticeCardMetrics.cardSize(cellSide:)` and the strip's size class.
public final class NoticeCardView: LayerBackedView {
    public var onClose: (() -> Void)?
    public var onAction: ((NoticeCard.Command) -> Void)?

    private var metrics = NoticeCardMetrics(sizeClass: .regular)
    private var command: NoticeCard.Command?
    private let iconView = SymbolView()
    private let titleLabel = NSTextField(wrappingLabelWithString: "")
    private let descriptionLabel = NSTextField(wrappingLabelWithString: "")
    private let closeButton = CloseButton()
    private let actionButton = NoticeActionButton()

    /// - Parameter closeButtonLabel: The close button's name for assistive technologies.
    public init(closeButtonLabel: String) {
        super.init(frame: .zero)

        layer?.cornerRadius = NoticeCardMetrics.cornerRadius
        layer?.cornerCurve = .circular
        layer?.masksToBounds = true

        iconView.tintColor = .labelColor
        titleLabel.textColor = .labelColor
        descriptionLabel.textColor = .secondaryLabelColor
        // Words wrap; only the last line that fits is cut short.
        for label in [titleLabel, descriptionLabel] {
            label.isSelectable = false
            label.lineBreakMode = .byWordWrapping
            label.cell?.truncatesLastVisibleLine = true
        }
        closeButton.target = self
        closeButton.action = #selector(closeButtonPressed)
        closeButton.setAccessibilityLabel(closeButtonLabel)

        actionButton.target = self
        actionButton.action = #selector(actionButtonPressed)

        for view in [iconView, titleLabel, descriptionLabel, closeButton, actionButton] {
            addSubview(view)
        }
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    override public var isFlipped: Bool { true }

    public func configure(with card: NoticeCard, sizeClass: SizeClass) {
        metrics = NoticeCardMetrics(sizeClass: sizeClass)

        let symbol = SymbolDescription(card.symbol, pointSize: metrics.symbolPointSize)
        iconView.symbol = symbol.makeImage() == nil
            ? SymbolDescription(NoticeCardMetrics.fallbackSymbolName, pointSize: metrics.symbolPointSize)
            : symbol
        titleLabel.stringValue = card.title
        titleLabel.font = metrics.titleFont
        descriptionLabel.stringValue = card.description ?? ""
        descriptionLabel.font = metrics.descriptionFont
        setAccessibilityLabel(card.title)

        command = card.action.command
        actionButton.title = card.action.title
        actionButton.controlSize = metrics.buttonControlSize
        actionButton.image = card.action.symbol.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        actionButton.imagePosition = .imageLeading
        needsLayout = true
    }

    /// Blends the card's layout from one density to another as the strip's density transition
    /// runs; `configure(with:sizeClass:)` has already given it the destination's type.
    public func transition(from source: SizeClass, to destination: SizeClass, progress: Double) {
        metrics = .blend(
            from: NoticeCardMetrics(sizeClass: source),
            to: NoticeCardMetrics(sizeClass: destination),
            progress: progress
        )
        needsLayout = true
    }

    override public func layout() {
        super.layout()
        let textWidth = bounds.width - NoticeCardMetrics.textLeadingInset - NoticeCardMetrics.textTrailingInset
        let layout = NoticeCardLayout(
            size: bounds.size,
            metrics: metrics,
            titleHeight: Self.height(of: titleLabel, width: textWidth),
            descriptionHeight: descriptionLabel.stringValue.isEmpty ? 0 : Self.height(of: descriptionLabel, width: textWidth),
            buttonHeight: actionButton.intrinsicContentSize.height
        )
        iconView.frame = layout.icon
        closeButton.frame = layout.closeButton
        titleLabel.frame = layout.title
        descriptionLabel.frame = layout.description
        actionButton.frame = layout.button
    }

    override public func updateLayerColors() {
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(NoticeCardMetrics.fillOpacity).cgColor
    }

    private static func height(of label: NSTextField, width: CGFloat) -> CGFloat {
        guard width > 0, let cell = label.cell else { return 0 }
        return ceil(cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height)
    }

    @objc private func closeButtonPressed() {
        onClose?()
    }

    @objc private func actionButtonPressed() {
        guard let command else { return }
        onAction?(command)
    }
}

/// A card's close button: a faint glyph that grows stronger while pressed, without the system's
/// highlight or any fill. With Increase Contrast on, the glyph is the secondary label colour at
/// rest and the label colour pressed.
private final class CloseButton: NSButton {
    init() {
        super.init(frame: .zero)
        image = SymbolDescription(NoticeCardMetrics.closeSymbolName, pointSize: NoticeCardMetrics.closeSymbolPointSize)
            .makeImage()
        imagePosition = .imageOnly
        isBordered = false
        (cell as? NSButtonCell)?.highlightsBy = []
        updateTint()
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CloseButton is created in code")
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateTint()
    }

    private func updateTint() {
        if NSWorkspace.shared.accessibilityDisplayShouldIncreaseContrast {
            contentTintColor = isHighlighted ? .labelColor : .secondaryLabelColor
            return
        }
        contentTintColor = isHighlighted
            ? .secondaryLabelColor
            : .labelColor.withAlphaComponent(NoticeCardMetrics.closeButtonOpacity)
    }

    /// Whatever thread the notification comes on, the glyph changes on the main one.
    @objc private nonisolated func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        Task { @MainActor in updateTint() }
    }
}
