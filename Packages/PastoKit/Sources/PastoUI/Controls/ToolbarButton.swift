import AppKit
import Symbols

/// A borderless capsule button showing a symbol, which gains a translucent fill under the pointer
/// and while pressed.
///
/// It acts when the mouse button goes up inside it: it reports the click or, when `menuProvider`
/// is set, opens that menu. It looks pressed from the moment the button goes down until it goes
/// up, wherever the pointer wanders meanwhile. A press stays with the button, as it does with a
/// system button: it does not continue up the responder chain. Its tracking area is always
/// active, also while something is being dragged: the panel it lives in is used while another
/// application is frontmost.
public final class ToolbarButton: LayerBackedView {
    public nonisolated enum Size: Sendable, CaseIterable {
        /// As wide as its content, with a minimum.
        case regular
        case medium
        case large

        public var height: CGFloat {
            switch self {
            case .regular: ToolbarButtonMetrics.regularHeight
            case .medium: ToolbarButtonMetrics.mediumSide
            case .large: ToolbarButtonMetrics.largeSide
            }
        }

        /// The button is a capsule: a circle for the two square sizes.
        public var cornerRadius: CGFloat { height / 2 }

        /// The button's size for content `contentWidth` wide. Only `regular` follows its content.
        public func size(contentWidth: CGFloat) -> CGSize {
            switch self {
            case .regular:
                let padded = contentWidth + 2 * ToolbarButtonMetrics.regularHorizontalPadding
                return CGSize(width: max(padded, ToolbarButtonMetrics.regularMinimumWidth), height: height)
            case .medium, .large:
                return CGSize(width: height, height: height)
            }
        }
    }

    public let size: Size

    /// Called when the button is clicked, or its key equivalent pressed. Not used while
    /// `menuProvider` is set.
    public var onClick: (() -> Void)?

    /// When set, pressing the button opens this menu instead of calling `onClick`.
    public var menuProvider: (() -> NSMenu)?

    /// The top-left corner of the menu in the button's coordinates (origin at the bottom-left
    /// corner). When nil the menu hangs from the button's bottom-left corner.
    public var menuOrigin: (() -> NSPoint)?

    public var keyEquivalent: KeyEquivalent?

    /// Drawn in place of the symbol, centred on the button at its intrinsic size, which may reach
    /// beyond the button's bounds (an animated icon, for one). Such an icon reacts to the pointer
    /// on its own, so the button then has no fill of its own, unless motion is reduced.
    public var iconView: NSView? {
        didSet {
            guard iconView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let iconView { addSubview(iconView) }
            symbolView.isHidden = iconView != nil
            needsLayout = true
            needsDisplay = true
        }
    }

    /// Called whenever the button starts or stops looking pressed.
    public var onPressedChange: ((Bool) -> Void)?

    /// The button stands for a mode that is on: it keeps a fill between the pointer's and the
    /// press's, which changes at once, without animation. Only the suggestions button uses it,
    /// while their mode is on.
    public var isSelected = false {
        didSet {
            guard isSelected != oldValue else { return }
            needsDisplay = true
            setAccessibilitySelected(isSelected)
        }
    }

    private let symbolView: SymbolView

    private var isHovered = false {
        didSet {
            if isHovered != oldValue { needsDisplay = true }
        }
    }

    private var isPressed = false {
        didSet {
            guard isPressed != oldValue else { return }
            needsDisplay = true
            onPressedChange?(isPressed)
        }
    }

    /// `accessibilityLabel` is what assistive technologies read: a symbol has no text of its own.
    public init(size: Size, symbol: SymbolDescription, accessibilityLabel: String) {
        self.size = size
        symbolView = SymbolView(symbol: symbol)
        super.init(frame: .zero)

        symbolView.tintColor = .labelColor
        addSubview(symbolView)
        setFrameSize(intrinsicContentSize)

        layer?.cornerRadius = size.cornerRadius

        // `.inVisibleRect` keeps the area in step with the view, so it is installed only once.
        // The pointer is followed during drags too: a card dragged over the button lights it up.
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag, .inVisibleRect],
            owner: self
        ))

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel)
    }

    override public var intrinsicContentSize: NSSize {
        size.size(contentWidth: symbolView.imageSize.width)
    }

    /// Plays a one-off effect on the button's symbol, such as a bounce.
    public func addSymbolEffect(_ effect: some DiscreteSymbolEffect & SymbolEffect, options: SymbolEffectOptions = .default) {
        symbolView.addSymbolEffect(effect, options: options)
    }

    override public func layout() {
        super.layout()
        symbolView.frame = bounds
        if let iconView {
            let size = iconView.intrinsicContentSize
            iconView.frame = NSRect(
                x: bounds.midX - size.width / 2,
                y: bounds.midY - size.height / 2,
                width: size.width,
                height: size.height
            )
        }
    }

    override public func updateLayerColors() {
        guard iconView == nil || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            layer?.backgroundColor = nil
            return
        }
        let opacity: CGFloat = if isPressed {
            ToolbarButtonMetrics.pressedFillOpacity
        } else if isSelected {
            ToolbarButtonMetrics.selectedFillOpacity
        } else if isHovered {
            ToolbarButtonMetrics.hoverFillOpacity
        } else {
            0
        }
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(opacity).cgColor
    }

    // MARK: - Mouse

    /// The whole capsule is the button: the image inside never takes the click.
    override public func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    /// The panel can be clicked while it is not key; the click should act, not just focus it.
    override public func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// The area is reinstalled whenever the button's place on screen changes — it is put in a
    /// window, the panel slides in under a resting pointer — and no entry event comes then: the
    /// pointer is looked for afresh, and any press is over.
    override public func updateTrackingAreas() {
        super.updateTrackingAreas()
        isHovered = NSEvent.pressedMouseButtons == 0 && isPointerInside
        isPressed = false
    }

    override public func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override public func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    /// The press is followed in a loop of its own until the button goes up, as a system button's
    /// is. The button looks pressed all along, wherever the pointer goes; the pointer's comings
    /// and goings wait until the end. Released inside, the button acts while it still looks
    /// pressed: a menu it opens is seen with the button down.
    override public func mouseDown(with event: NSEvent) {
        isPressed = true
        guard let window else { return }
        var release: NSEvent?
        window.trackEvents(matching: [.leftMouseDragged, .leftMouseUp], timeout: .infinity, mode: .eventTracking) { event, stop in
            guard let event, event.type == .leftMouseUp else { return }
            release = event
            stop.pointee = true
        }
        if let release, bounds.contains(convert(release.locationInWindow, from: nil)) {
            activate()
        }
        isPressed = false
    }

    override public func viewDidHide() {
        super.viewDidHide()
        // A hidden view gets no exit event.
        isHovered = false
        isPressed = false
    }

    // MARK: - Keyboard

    // With "Keyboard navigation" on in System Settings, Tab reaches the button and Space or
    // Return presses it, with a focus ring in its capsule; otherwise it stays out of the key view
    // loop, as a system button does.

    /// Only the keyboard gives the button the focus: a click leaves it where it was — on the
    /// strip, say, whose arrows keep moving the selection.
    override public var acceptsFirstResponder: Bool {
        NSApp.isFullKeyboardAccessEnabled && !Self.isMouseDown(NSApp.currentEvent)
    }

    /// Not while it is out of sight: hidden, or faded out under something else (the search
    /// field covers the magnifier that way).
    override public var canBecomeKeyView: Bool {
        NSApp.isFullKeyboardAccessEnabled && !isHiddenOrHasHiddenAncestor && alphaValue > 0
    }

    private static func isMouseDown(_ event: NSEvent?) -> Bool {
        guard let event else { return false }
        return [.leftMouseDown, .rightMouseDown, .otherMouseDown].contains(event.type)
    }

    override public func keyDown(with event: NSEvent) {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              [" ", "\r"].contains(event.charactersIgnoringModifiers)
        else { return super.keyDown(with: event) }
        activate()
    }

    override public var focusRingMaskBounds: NSRect {
        bounds
    }

    override public func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: size.cornerRadius, yRadius: size.cornerRadius).fill()
    }

    // MARK: - Activation

    override public func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let keyEquivalent, !isHiddenOrHasHiddenAncestor, keyEquivalent.matches(event) else {
            return super.performKeyEquivalent(with: event)
        }
        activate()
        return true
    }

    override public func accessibilityPerformPress() -> Bool {
        activate()
        return true
    }

    private func activate() {
        guard let menuProvider else {
            onClick?()
            return
        }
        let menu = menuProvider()
        let origin = menuOrigin?() ?? NSPoint(x: bounds.minX, y: bounds.minY)

        // The menu runs its own event loop: show the pressed fill before entering it, and work
        // out the pointer's position afterwards, because the exit event is lost meanwhile.
        isPressed = true
        displayIfNeeded()
        menu.popUp(positioning: nil, at: origin, in: self)
        isPressed = false
        isHovered = isPointerInside
    }

    private var isPointerInside: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }
}
