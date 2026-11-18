import AppKit
import PastoUI

/// The toolbar's notice that capture is paused: a button that opens the pause menu, which says
/// until when as its tooltip. Without a pause it shows nothing and takes no room; it comes and
/// goes at once.
final class PauseIndicatorView: NSView {
    var status = PauseStatus.running {
        didSet {
            guard status != oldValue else { return }
            let text = status.indicatorText()
            button.toolTip = text
            isHidden = text == nil
            invalidateIntrinsicContentSize()
            needsLayout = true
        }
    }

    /// Builds the menu the button opens: the app's pause menu.
    var menuProvider: (() -> NSMenu)?

    private let button = ToolbarButton(
        size: ToolbarMetrics.pauseButtonSize,
        symbol: ToolbarMetrics.pauseSymbol,
        accessibilityLabel: PanelStrings.pauseButton
    )

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        isHidden = true
        addSubview(button)

        button.menuProvider = { [weak self] in self?.menuProvider?() ?? NSMenu() }
        button.menuOrigin = { [weak button] in
            let bounds = button?.bounds ?? .zero
            return NSPoint(x: bounds.minX, y: bounds.maxY + ToolbarMetrics.pauseMenuTopOverlap)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PauseIndicatorView is created in code")
    }

    /// Only the width means something: the toolbar gives the indicator its full height.
    override var intrinsicContentSize: NSSize {
        NSSize(width: isHidden ? 0 : button.frame.width, height: NSView.noIntrinsicMetric)
    }

    override func layout() {
        super.layout()
        button.setFrameOrigin(NSPoint(x: 0, y: ((bounds.height - button.frame.height) / 2).rounded()))
    }
}
