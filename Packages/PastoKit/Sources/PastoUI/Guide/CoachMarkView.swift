import AppKit

/// A small glass label that explains one element of a window: a title, a line or two, and its
/// buttons. It lives inside the window it explains — no window of its own, so it never takes the
/// focus or changes what is key — and its buttons answer clicks only: Return, Space and Escape
/// stay the window's.
///
/// VoiceOver finds it as a popover named after its title, with its text and buttons inside.
public final class CoachMarkView: NSView {
    public struct Content: Equatable, Sendable {
        public var title: String
        public var message: String
        /// "2 of 5"; nil when the mark is not part of a tour.
        public var step: String?
        /// "Next", "Done" or "Got It".
        public var primaryTitle: String
        /// "Skip"; nil for no second button.
        public var secondaryTitle: String?

        public init(title: String, message: String, step: String?, primaryTitle: String, secondaryTitle: String?) {
            self.title = title
            self.message = message
            self.step = step
            self.primaryTitle = primaryTitle
            self.secondaryTitle = secondaryTitle
        }
    }

    public var onPrimary: (() -> Void)?
    public var onSecondary: (() -> Void)?

    private let glassView = NSGlassEffectView(frame: .zero)
    private let contentView = NSView(frame: .zero)
    private let titleLabel = NSTextField(labelWithString: "")
    private let messageLabel = NSTextField(wrappingLabelWithString: "")
    private let stepLabel = NSTextField(labelWithString: "")
    private let primaryButton = NSButton(title: "", target: nil, action: nil)
    private let secondaryButton = NSButton(title: "", target: nil, action: nil)
    private(set) public var content: Content?

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        glassView.cornerRadius = CoachMarkMetrics.cornerRadius
        // Over cards full of text, clear glass leaves the label hard to read: a tint gives its
        // own text a calm ground.
        glassView.tintColor = NSColor.windowBackgroundColor.withAlphaComponent(0.82)
        glassView.contentView = contentView
        addSubview(glassView)

        titleLabel.font = .systemFont(ofSize: CoachMarkMetrics.titleFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byWordWrapping
        titleLabel.cell?.wraps = true
        titleLabel.maximumNumberOfLines = 2
        messageLabel.font = .systemFont(ofSize: CoachMarkMetrics.messageFontSize)
        messageLabel.textColor = .labelColor
        messageLabel.isSelectable = false
        stepLabel.font = .systemFont(ofSize: CoachMarkMetrics.stepFontSize)
        stepLabel.textColor = .secondaryLabelColor
        for button in [primaryButton, secondaryButton] {
            button.bezelStyle = .push
            button.controlSize = .small
            button.font = .systemFont(ofSize: NSFont.systemFontSize(for: .small))
            button.target = self
            // Clicks only: the keys belong to the window the mark explains.
            button.keyEquivalent = ""
            button.refusesFirstResponder = true
        }
        primaryButton.bezelColor = .controlAccentColor
        primaryButton.action = #selector(primaryAction)
        secondaryButton.action = #selector(secondaryAction)
        for view in [titleLabel, messageLabel, stepLabel, secondaryButton, primaryButton] {
            contentView.addSubview(view)
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.popover)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("CoachMarkView is created in code")
    }

    public func configure(_ content: Content) {
        self.content = content
        titleLabel.stringValue = content.title
        messageLabel.stringValue = content.message
        stepLabel.stringValue = content.step ?? ""
        stepLabel.isHidden = content.step == nil
        primaryButton.title = content.primaryTitle
        secondaryButton.title = content.secondaryTitle ?? ""
        secondaryButton.isHidden = content.secondaryTitle == nil
        primaryButton.sizeToFit()
        secondaryButton.sizeToFit()
        setAccessibilityLabel(content.title)
        needsLayout = true
    }

    /// The size the mark needs for its content, at its fixed width.
    public var fittingContentSize: NSSize {
        let width = CoachMarkMetrics.width
        let textWidth = width - 2 * CoachMarkMetrics.padding
        let height = CoachMarkMetrics.padding
            + textHeight(of: titleLabel, width: textWidth)
            + CoachMarkMetrics.titleSpacing
            + textHeight(of: messageLabel, width: textWidth)
            + CoachMarkMetrics.footerSpacing
            + footerHeight
            + CoachMarkMetrics.padding
        return NSSize(width: width, height: height.rounded(.up))
    }

    override public func layout() {
        super.layout()
        glassView.frame = bounds
        contentView.frame = glassView.bounds
        let padding = CoachMarkMetrics.padding
        let textWidth = bounds.width - 2 * padding
        var top = bounds.height - padding

        let titleHeight = textHeight(of: titleLabel, width: textWidth)
        titleLabel.frame = NSRect(x: padding, y: top - titleHeight, width: textWidth, height: titleHeight)
        top -= titleHeight + CoachMarkMetrics.titleSpacing

        let messageHeight = textHeight(of: messageLabel, width: textWidth)
        messageLabel.frame = NSRect(x: padding, y: top - messageHeight, width: textWidth, height: messageHeight)

        // The footer: the step on the leading side, the buttons on the trailing one.
        let footerY = padding
        var trailing = bounds.width - padding
        let primarySize = primaryButton.fittingSize
        primaryButton.frame = NSRect(
            x: trailing - primarySize.width,
            y: footerY + (footerHeight - primarySize.height) / 2,
            width: primarySize.width,
            height: primarySize.height
        )
        trailing = primaryButton.frame.minX - CoachMarkMetrics.buttonSpacing
        if !secondaryButton.isHidden {
            let secondarySize = secondaryButton.fittingSize
            secondaryButton.frame = NSRect(
                x: trailing - secondarySize.width,
                y: footerY + (footerHeight - secondarySize.height) / 2,
                width: secondarySize.width,
                height: secondarySize.height
            )
            trailing = secondaryButton.frame.minX - CoachMarkMetrics.buttonSpacing
        }
        let stepSize = stepLabel.fittingSize
        stepLabel.frame = NSRect(
            x: padding,
            y: footerY + (footerHeight - stepSize.height) / 2,
            width: max(0, min(stepSize.width, trailing - padding)),
            height: stepSize.height
        )
    }

    private var footerHeight: CGFloat {
        max(primaryButton.fittingSize.height, secondaryButton.fittingSize.height, stepLabel.fittingSize.height)
    }

    private func textHeight(of label: NSTextField, width: CGFloat) -> CGFloat {
        guard !label.stringValue.isEmpty, let cell = label.cell else { return 0 }
        return cell.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height.rounded(.up)
    }

    /// The window under the mark keeps its cursor and its clicks around the mark, not inside it.
    override public func hitTest(_ point: NSPoint) -> NSView? {
        guard !isHidden, alphaValue > 0 else { return nil }
        return super.hitTest(point)
    }

    @objc private func primaryAction() {
        onPrimary?()
    }

    @objc private func secondaryAction() {
        onSecondary?()
    }
}
