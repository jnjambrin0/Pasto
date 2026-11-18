import AppKit
import PastoCoreUI
import PastoUI

/// The capsule button of the preview's headers and footers: a title, a symbol or both, and
/// optionally the arrow of a button that opens a menu. It can be the primary action of its
/// header (Save, Create), show an "on" state (the formatting buttons) and be disabled. A button
/// with a title is a faint capsule at rest; one with only a symbol is smaller and shows its fill
/// only under the pointer. It follows the pointer even during a drag, and checks it again
/// whenever its tracking area is updated, so that a button appearing under the pointer shows as
/// hovered.
///
/// The toolbar's button (`PastoUI.ToolbarButton`) only shows a symbol and cannot live in a
/// window that moves by its background, hence a control of its own.
final class PreviewButton: LayerBackedView {
    /// Called with the button, which callers use as the anchor of menus and pickers.
    var onClick: ((PreviewButton) -> Void)?
    var keyEquivalent: KeyEquivalent?

    var isEnabled = true {
        didSet {
            guard isEnabled != oldValue else { return }
            if !isEnabled { isPressed = false }
            restyle()
        }
    }

    /// The main action of a header: filled with the accent colour.
    var isPrimary = false {
        didSet { restyle() }
    }

    var isSelected = false {
        didSet {
            if isSelected != oldValue { restyle() }
        }
    }

    /// A button that turns something on and off, such as bold: assistive technologies see a
    /// checkbox whose value is `isSelected`.
    var isToggle = false {
        didSet { setAccessibilityRole(isToggle ? .checkBox : .button) }
    }

    /// Tint of the symbol, in every state but the primary one; the content colour when nil.
    var symbolTint: NSColor? {
        didSet { restyle() }
    }

    private let titleLabel: NSTextField?
    private let symbolView: SymbolView?
    /// The arrow of a button that opens a menu: the system's symbol at its own size, always in
    /// the soft label colour.
    private let pullDownArrowView: NSImageView?

    private var isHovered = false {
        didSet {
            if isHovered != oldValue { restyle() }
        }
    }

    private var isPressed = false {
        didSet {
            if isPressed != oldValue { restyle() }
        }
    }

    /// - Parameters:
    ///   - accessibilityLabel: What assistive technologies read; the title when nil.
    ///   - showsPullDownArrow: Ends the button with a downward chevron, for one that opens a menu.
    init(title: String? = nil, symbolName: String? = nil, accessibilityLabel: String? = nil, showsPullDownArrow: Bool = false) {
        titleLabel = title.map { title in
            let label = NSTextField(labelWithString: title)
            label.font = .preferredFont(forTextStyle: .body)
            return label
        }
        symbolView = symbolName.map {
            SymbolView(symbol: SymbolDescription($0, pointSize: PreviewMetrics.buttonSymbolPointSize))
        }
        pullDownArrowView = showsPullDownArrow ? Self.makePullDownArrowView() : nil
        super.init(frame: .zero)

        [symbolView, titleLabel, pullDownArrowView].compactMap(\.self).forEach(addSubview)
        layer?.cornerRadius = height / 2
        translatesAutoresizingMaskIntoConstraints = false
        setContentHuggingPriority(.required, for: .horizontal)
        setContentCompressionResistancePriority(.required, for: .horizontal)
        restyle()

        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .enabledDuringMouseDrag, .inVisibleRect],
            owner: self
        ))

        setAccessibilityElement(true)
        setAccessibilityRole(.button)
        setAccessibilityLabel(accessibilityLabel ?? title)
    }

    private static func makePullDownArrowView() -> NSImageView {
        // No symbol configuration: the arrow keeps the size the system gives it.
        let arrow = NSImageView(image: NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil) ?? NSImage())
        arrow.imageScaling = .scaleNone
        arrow.contentTintColor = ItemPresentation.primaryTextColor
        return arrow
    }

    /// Changes the symbol of a button that was created with one.
    func setSymbol(_ name: String) {
        symbolView?.symbol = SymbolDescription(name, pointSize: PreviewMetrics.buttonSymbolPointSize)
        invalidateIntrinsicContentSize()
        needsLayout = true
    }

    // MARK: - Layout

    private var hasTitle: Bool { titleLabel != nil }

    private var height: CGFloat {
        hasTitle ? PreviewMetrics.titledButtonHeight : PreviewMetrics.symbolButtonHeight
    }

    private var horizontalPadding: CGFloat {
        hasTitle ? PreviewMetrics.titledButtonPadding : PreviewMetrics.symbolButtonPadding
    }

    private var symbolWidth: CGFloat { symbolView?.imageSize.width ?? 0 }
    /// The width of the title's text, without the margins of the field that draws it.
    private var titleWidth: CGFloat { titleLabel?.intrinsicContentSize.width ?? 0 }
    private var arrowSize: NSSize { pullDownArrowView?.image?.size ?? .zero }

    /// The symbol, the title and the arrow, in that order, with the same spacing between them.
    private var contentWidth: CGFloat {
        let widths = [
            symbolView.map { _ in symbolWidth },
            titleLabel.map { _ in titleWidth },
            pullDownArrowView.map { _ in arrowSize.width },
        ].compactMap(\.self)
        return widths.reduce(0, +) + CGFloat(max(widths.count - 1, 0)) * PreviewMetrics.buttonContentSpacing
    }

    override var intrinsicContentSize: NSSize {
        NSSize(
            width: max(contentWidth + 2 * horizontalPadding, PreviewMetrics.buttonMinimumWidth),
            height: height
        )
    }

    override func layout() {
        super.layout()
        var x = ((bounds.width - contentWidth) / 2).rounded()
        if let symbolView {
            symbolView.frame = NSRect(x: x, y: 0, width: symbolWidth, height: bounds.height)
            x += symbolWidth + PreviewMetrics.buttonContentSpacing
        }
        if let titleLabel {
            let height = titleLabel.intrinsicContentSize.height
            let textRect = NSRect(x: x, y: ((bounds.height - height) / 2).rounded(), width: titleWidth, height: height)
            // A label's intrinsic size is that of its text. The field is wider: its cell keeps
            // a margin at each side, and a frame of the text's width alone cuts the text short.
            titleLabel.frame = titleLabel.frame(forAlignmentRect: textRect)
            x += titleWidth + PreviewMetrics.buttonContentSpacing
        }
        if let pullDownArrowView {
            let size = arrowSize
            pullDownArrowView.frame = NSRect(
                origin: NSPoint(x: x, y: ((bounds.height - size.height) / 2).rounded()),
                size: size
            )
        }
    }

    // MARK: - Appearance

    /// A primary button keeps its colours under the pointer; pressing or disabling it changes
    /// them the way the system changes a control's.
    private var primaryEffect: NSColor.SystemEffect {
        if !isEnabled { .disabled } else if isPressed { .pressed } else { .none }
    }

    /// The colour of the title and the symbol: a soft black or white at rest, the full label
    /// colour while pressed or on.
    private var contentColor: NSColor {
        if isPrimary {
            NSColor.white.withSystemEffect(primaryEffect)
        } else if !isEnabled {
            NSColor.secondaryLabelColor.withSystemEffect(.disabled)
        } else if isPressed {
            isSelected ? .secondaryLabelColor : .labelColor
        } else if isSelected {
            .labelColor
        } else {
            ItemPresentation.primaryTextColor
        }
    }

    /// The fill's opacity for a button that is not primary. A disabled one looks as at rest.
    private var fillOpacity: CGFloat {
        if isEnabled, isPressed {
            PreviewMetrics.buttonPressedFillOpacity
        } else if isEnabled, isSelected {
            PreviewMetrics.buttonSelectedFillOpacity
        } else if isEnabled, isHovered {
            hasTitle ? PreviewMetrics.titledButtonHoverFillOpacity : PreviewMetrics.symbolButtonHoverFillOpacity
        } else {
            hasTitle ? PreviewMetrics.titledButtonRestFillOpacity : 0
        }
    }

    private func restyle() {
        let contentColor = contentColor
        titleLabel?.textColor = contentColor
        symbolView?.tintColor = isPrimary ? contentColor : symbolTint ?? contentColor
        needsDisplay = true
    }

    override func updateLayerColors() {
        let fill = isPrimary
            ? NSColor.controlAccentColor.withSystemEffect(primaryEffect)
            : PreviewColor.ink(fillOpacity)
        layer?.backgroundColor = fill.cgColor
    }

    // MARK: - Mouse

    /// The whole capsule is the button: what is inside never takes the click.
    override func hitTest(_ point: NSPoint) -> NSView? {
        super.hitTest(point) == nil ? nil : self
    }

    /// The preview's window moves by its background; a press on the button must not drag it.
    override var mouseDownCanMoveWindow: Bool { false }

    /// The popover is used while its window is not key; the click should act, not just focus it.
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    /// Called when the button joins a window and whenever its geometry changes: what is under the
    /// pointer is looked at again, as if it had just entered or left, and a press is dropped.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        isHovered = NSEvent.pressedMouseButtons == 0 && isUnderPointer
        isPressed = false
    }

    private var isUnderPointer: Bool {
        guard let window else { return false }
        return bounds.contains(convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    /// The button stays pressed until the mouse goes up, wherever it is dragged meanwhile, and
    /// acts only if it goes up over the button.
    override func mouseDown(with event: NSEvent) {
        isPressed = isEnabled
    }

    /// The drag stays with the button: it neither changes the press nor reaches the views below.
    override func mouseDragged(with event: NSEvent) {}

    override func mouseUp(with event: NSEvent) {
        guard isPressed else { return }
        isPressed = false
        guard bounds.contains(convert(event.locationInWindow, from: nil)) else { return }
        onClick?(self)
    }

    override func viewDidHide() {
        super.viewDidHide()
        // A hidden view gets no exit event.
        isHovered = false
        isPressed = false
    }

    // MARK: - Activation

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard let keyEquivalent, isEnabled, !isHiddenOrHasHiddenAncestor, keyEquivalent.matches(event) else {
            return super.performKeyEquivalent(with: event)
        }
        onClick?(self)
        return true
    }

    override func accessibilityPerformPress() -> Bool {
        guard isEnabled else { return false }
        onClick?(self)
        return true
    }

    override func isAccessibilityEnabled() -> Bool { isEnabled }

    override func accessibilityValue() -> Any? {
        isToggle ? NSNumber(value: isSelected) : nil
    }

    // MARK: - Keyboard

    // With "Keyboard navigation" on in System Settings, Tab reaches the button and Space or
    // Return presses it; otherwise it stays out of the key view loop, as a toolbar button does.

    override var acceptsFirstResponder: Bool {
        isEnabled && NSApp.isFullKeyboardAccessEnabled
    }

    override var canBecomeKeyView: Bool {
        acceptsFirstResponder
    }

    override func keyDown(with event: NSEvent) {
        guard isEnabled, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty,
              [" ", "\r"].contains(event.charactersIgnoringModifiers)
        else { return super.keyDown(with: event) }
        onClick?(self)
    }

    override var focusRingMaskBounds: NSRect {
        bounds
    }

    override func drawFocusRingMask() {
        NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2).fill()
    }
}
