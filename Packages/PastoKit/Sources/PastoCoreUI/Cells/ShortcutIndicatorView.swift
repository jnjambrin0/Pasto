import AppKit

/// The capsule in a card's bottom-right corner that appears while a paste modifier is held: the
/// card's quick paste number, a plain-text glyph, or both.
final class ShortcutIndicatorView: CardView {
    /// What decides the indicator's content besides the card's own number.
    struct Settings {
        var plainTextModifierFlags: NSEvent.ModifierFlags
        var quickPasteModifierFlags: NSEvent.ModifierFlags
        /// The modifier keys held right now.
        var currentModifierFlags: () -> NSEvent.ModifierFlags
    }

    var quickPasteIndex: Int? {
        didSet {
            guard quickPasteIndex != oldValue else { return }
            numberLabel.stringValue = quickPasteIndex.map(String.init) ?? ""
            numberWidth = numberLabel.intrinsicContentSize.width
            refresh()
        }
    }

    /// False while the strip does not have keyboard focus, which hides the indicator.
    var isEnabled = true {
        didSet {
            if isEnabled != oldValue { refresh() }
        }
    }

    /// `nil` until the cell is configured; the indicator stays hidden meanwhile.
    var settings: Settings? {
        didSet { refresh() }
    }

    private let backdropView = BackdropView()
    private let glyphView = NSImageView()
    private let numberLabel = NSTextField.cardLabel(font: .callout, color: .secondary)

    private let glyphSize: CGSize
    private var numberWidth: CGFloat = 0
    private var visibility = ShortcutIndicatorVisibility.hidden
    /// The corner the capsule hangs from, in the superview's coordinates.
    private var trailingBottom = CGPoint.zero

    private var flagsMonitor: Any?
    private var keyWindowObserver: (any NSObjectProtocol)?

    override init(frame frameRect: NSRect) {
        let symbol = NSImage(systemSymbolName: "text.justify.leading", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "questionmark.square", accessibilityDescription: nil)
        let glyph = symbol?.withSymbolConfiguration(NSImage.SymbolConfiguration(textStyle: .footnote))
        glyphSize = glyph?.size ?? .zero
        super.init(frame: frameRect)

        layer?.cornerRadius = ShortcutIndicatorMetrics.height / 2
        clipsToBounds = true
        isHidden = true

        glyphView.image = glyph
        glyphView.contentTintColor = NSColor.dynamic(
            light: NSColor.black.withAlphaComponent(ShortcutIndicatorMetrics.glyphAlpha),
            dark: NSColor.white.withAlphaComponent(ShortcutIndicatorMetrics.glyphAlpha)
        )

        addSubview(backdropView)
        addSubview(glyphView)
        addSubview(numberLabel)
    }

    isolated deinit {
        stopObserving()
    }

    /// Hangs the capsule from `point`, its bottom-right corner. Its width follows its content.
    func place(trailingBottomAt point: CGPoint) {
        trailingBottom = point
        updateFrame()
    }

    // MARK: - Refreshing

    /// The indicator follows the keyboard only while it is in a window: it listens for modifier
    /// changes and for the window becoming key, when keys pressed elsewhere may have changed.
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        stopObserving()
        guard let window else { return }

        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            MainActor.assumeIsolated {
                self?.refresh()
            }
            return event
        }
        keyWindowObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didBecomeKeyNotification, object: window, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        refresh()
    }

    private func stopObserving() {
        if let flagsMonitor { NSEvent.removeMonitor(flagsMonitor) }
        if let keyWindowObserver { NotificationCenter.default.removeObserver(keyWindowObserver) }
        flagsMonitor = nil
        keyWindowObserver = nil
    }

    private func refresh() {
        visibility = settings.map { settings in
            ShortcutIndicatorVisibility(
                isEnabled: isEnabled,
                heldFlags: settings.currentModifierFlags().intersection(.deviceIndependentFlagsMask),
                plainTextFlags: settings.plainTextModifierFlags,
                quickPasteFlags: settings.quickPasteModifierFlags,
                quickPasteIndex: quickPasteIndex
            )
        } ?? .hidden
        isHidden = !visibility.isVisible
        glyphView.isHidden = !visibility.showsPlainTextGlyph
        numberLabel.isHidden = !visibility.showsNumber
        updateFrame()
    }

    // MARK: - Layout

    private func updateFrame() {
        let metrics = ShortcutIndicatorMetrics.self
        var contentWidth: CGFloat = 0
        if visibility.showsPlainTextGlyph { contentWidth += glyphSize.width }
        if visibility.showsPlainTextGlyph, visibility.showsNumber { contentWidth += metrics.spacing }
        if visibility.showsNumber { contentWidth += numberWidth }

        let width = contentWidth + 2 * metrics.horizontalPadding
        frame = CGRect(x: trailingBottom.x - width, y: trailingBottom.y - metrics.height, width: width, height: metrics.height)
        needsLayout = true
    }

    override func layout() {
        super.layout()
        let metrics = ShortcutIndicatorMetrics.self
        backdropView.frame = bounds

        var x = metrics.horizontalPadding
        if visibility.showsPlainTextGlyph {
            glyphView.frame = CGRect(
                x: x, y: ((bounds.height - glyphSize.height) / 2).rounded(), width: glyphSize.width, height: glyphSize.height
            )
            x += glyphSize.width + metrics.spacing
        }
        let numberHeight = numberLabel.intrinsicContentSize.height
        numberLabel.setAlignmentRect(CGRect(x: x, y: (bounds.height - numberHeight) / 2, width: numberWidth, height: numberHeight))
    }
}
