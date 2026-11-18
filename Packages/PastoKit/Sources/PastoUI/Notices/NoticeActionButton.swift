import AppKit

/// A notice card's button: its title on a faint capsule that darkens while pressed, with room
/// around the title.
final class NoticeActionButton: NSButton {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isBordered = false
        wantsLayer = true
        layer?.cornerCurve = .circular
        updateFill()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoticeActionButton is created in code")
    }

    /// A capsule whatever its height.
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        layer?.cornerRadius = newSize.height / 2
    }

    override var intrinsicContentSize: NSSize {
        let title = super.intrinsicContentSize
        let insets = NoticeCardMetrics.buttonContentInsets
        return NSSize(width: title.width + insets.left + insets.right, height: title.height + insets.top + insets.bottom)
    }

    override func highlight(_ flag: Bool) {
        super.highlight(flag)
        updateFill()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateFill()
    }

    private func updateFill() {
        let opacity = isHighlighted ? NoticeCardMetrics.buttonHighlightedFillOpacity : NoticeCardMetrics.buttonFillOpacity
        effectiveAppearance.performAsCurrentDrawingAppearance {
            layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(opacity).cgColor
        }
    }
}
