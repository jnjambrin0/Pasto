import AppKit

/// What the strip shows in suggestions mode while it has no cards: a line saying there is nothing
/// to suggest or, while screen recording access is missing, a block that asks for it with a
/// button to allow it and one to turn suggestions off. There is no loading state: the wave covers
/// the wait.
final class PicksPlaceholderView: NSView {
    var onAllowAccess: (() -> Void)?
    var onTurnOff: (() -> Void)?

    /// Whether the block that asks for screen recording access takes the place of the line.
    var showsAccessRequest = false {
        didSet {
            guard showsAccessRequest != oldValue else { return }
            updateVisibility()
            needsLayout = true
        }
    }

    private typealias Metrics = PicksPanelMetrics

    private let emptyLabel = NSTextField(labelWithString: PicksStrings.empty)
    private let icon = PicksIconView(side: PicksIconMetrics.placeholderSide, respondsToPointer: false)
    private let titleLabel = NSTextField(labelWithString: PicksStrings.accessTitle)
    private let subtitleLabel = NSTextField(wrappingLabelWithString: PicksStrings.accessSubtitle)
    private let allowButton = NSButton(title: PicksStrings.allowAccess, target: nil, action: nil)
    private let turnOffButton = NSButton(title: PicksStrings.turnOffMenuItem, target: nil, action: nil)

    private var accessViews: [NSView] {
        [icon, titleLabel, subtitleLabel, allowButton, turnOffButton]
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        emptyLabel.font = MainPanelMetrics.emptyTextFont
        emptyLabel.textColor = MainPanelMetrics.emptyTextColor
        emptyLabel.alignment = .center

        titleLabel.font = .systemFont(ofSize: Metrics.accessTitleFontSize, weight: .semibold)
        titleLabel.textColor = .labelColor
        titleLabel.alignment = .center

        subtitleLabel.font = .systemFont(ofSize: Metrics.accessSubtitleFontSize)
        subtitleLabel.textColor = .secondaryLabelColor
        subtitleLabel.alignment = .center
        subtitleLabel.isSelectable = false
        subtitleLabel.preferredMaxLayoutWidth = Metrics.accessSubtitleMaximumWidth

        allowButton.controlSize = .large
        allowButton.target = self
        allowButton.action = #selector(allowAccess)

        turnOffButton.isBordered = false
        turnOffButton.contentTintColor = .secondaryLabelColor
        turnOffButton.target = self
        turnOffButton.action = #selector(turnOff)

        for view in [emptyLabel] + accessViews {
            addSubview(view)
        }
        updateVisibility()

        // The empty line's colour depends on Increase Contrast too.
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(accessibilityDisplayOptionsDidChange),
            name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
            object: nil
        )
    }

    /// Whatever thread the notification comes on, the text changes on the main one.
    @objc private nonisolated func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
        Task { @MainActor in emptyLabel.textColor = MainPanelMetrics.emptyTextColor }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PicksPlaceholderView is created in code")
    }

    override func layout() {
        super.layout()
        let emptySize = emptyLabel.fittingSize
        emptyLabel.frame = NSRect(
            x: (bounds.midX - emptySize.width / 2).rounded(),
            y: (MainPanelMetrics.emptyTextCenterY(in: bounds) - emptySize.height / 2).rounded(),
            width: emptySize.width,
            height: emptySize.height
        )

        let layout = PicksPlaceholderLayout(
            sizes: PicksPlaceholderLayout.Sizes(
                icon: icon.intrinsicContentSize,
                title: titleLabel.fittingSize,
                subtitle: subtitleSize(),
                primaryButton: allowButton.fittingSize,
                secondaryButton: turnOffButton.fittingSize
            ),
            in: bounds
        )
        icon.frame = layout.icon
        titleLabel.frame = layout.title
        subtitleLabel.frame = layout.subtitle
        allowButton.frame = layout.primaryButton
        turnOffButton.frame = layout.secondaryButton
    }

    /// The subtitle wraps at its maximum width.
    private func subtitleSize() -> NSSize {
        let bounds = NSRect(x: 0, y: 0, width: Metrics.accessSubtitleMaximumWidth, height: .greatestFiniteMagnitude)
        let size = subtitleLabel.cell?.cellSize(forBounds: bounds) ?? .zero
        return NSSize(width: ceil(size.width), height: ceil(size.height))
    }

    private func updateVisibility() {
        emptyLabel.isHidden = showsAccessRequest
        for view in accessViews {
            view.isHidden = !showsAccessRequest
        }
    }

    /// Only the buttons take clicks; anything else goes to the strip underneath.
    override func hitTest(_ point: NSPoint) -> NSView? {
        let hit = super.hitTest(point)
        return hit is NSButton ? hit : nil
    }

    @objc private func allowAccess() {
        onAllowAccess?()
    }

    @objc private func turnOff() {
        onTurnOff?()
    }
}
