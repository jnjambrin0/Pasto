import AppKit
import PastoUI

/// What every card has in common: a rounded content view, the selection ring behind it and a
/// faint shadow. There is no hover or pressed state.
open class BaseCell: CollectionViewCell {
    /// The card. Everything a card shows goes inside; it clips to the rounded corners.
    let contentView = CardView(frame: .zero)

    /// The selection ring. It is not a stroke: it is a filled view that sticks out behind the
    /// card, so what shows is the band around it.
    private let selectionView = CardView(frame: .zero)
    /// Whether the ring was showing after the previous change of selection or focus.
    private var ringWasShown = false
    private static let focusFadeKey = "focusFade"

    /// The card's fill. The content's appearance follows it, so that text tokens come out dark
    /// on a light card and light on a dark one whatever the system mode is.
    var cardBackground = CardBackground.standard {
        didSet {
            if cardBackground != oldValue { applyBackground() }
        }
    }

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        selectionView.layer?.cornerRadius = BaseCellMetrics.selectionCornerRadius
        selectionView.layer?.cornerCurve = .continuous
        addSubview(selectionView)

        contentView.layer?.cornerRadius = BaseCellMetrics.cornerRadius
        contentView.layer?.cornerCurve = .continuous
        contentView.clipsToBounds = true
        addSubview(contentView)

        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(BaseCellMetrics.shadowAlpha)
        shadow.shadowOffset = .zero
        shadow.shadowBlurRadius = BaseCellMetrics.shadowBlurRadius
        self.shadow = shadow

        applyBackground()
    }

    override open var isFlipped: Bool { true }

    /// Cards are laid out by hand, so a new size always means a new layout pass.
    override open func setFrameSize(_ newSize: NSSize) {
        let isChange = newSize != frame.size
        super.setFrameSize(newSize)
        if isChange { needsLayout = true }
    }

    override open func layout() {
        super.layout()
        contentView.frame = bounds
        selectionView.frame = bounds.insetBy(dx: -BaseCellMetrics.selectionOutset, dy: -BaseCellMetrics.selectionOutset)
        updateShadowPath()
    }

    override open func selectionDidChange() {
        // Called for a change of either flag. While the card stays selected it can only be the
        // strip gaining or losing keyboard focus: then the ring fades between blue and grey. A
        // ring that comes or goes — the selection moving — changes at once.
        let fadesFocusChange = isSelected && ringWasShown && window != nil
        ringWasShown = isSelected

        let fill: NSColor? = isSelected ? (isEmphasized ? .controlAccentColor : Self.mutedSelectionColor) : nil
        if fadesFocusChange {
            fadeSelectionRing(to: fill)
        } else {
            selectionView.layer?.removeAnimation(forKey: Self.focusFadeKey)
            selectionView.fillColor = fill
        }
        updateShadowPath()
    }

    /// Sets the ring's colour and fades the layer from whatever it shows now, mid-fade included.
    /// Core Animation interpolates between the accent colour, in sRGB, and the grey, in a grey
    /// colour space, so the channels do not move in step.
    private func fadeSelectionRing(to fill: NSColor?) {
        guard let layer = selectionView.layer else {
            selectionView.fillColor = fill
            return
        }
        let from = layer.presentation()?.backgroundColor ?? layer.backgroundColor
        var to: CGColor?
        selectionView.effectiveAppearance.performAsCurrentDrawingAppearance { to = fill?.cgColor }
        selectionView.fillColor = fill
        // The view would assign the same colour on its next display; it is set now so that the
        // model value is the end of the fade.
        layer.backgroundColor = to

        let fade = CABasicAnimation(keyPath: "backgroundColor")
        fade.fromValue = from
        fade.toValue = to
        fade.duration = BaseCellMetrics.focusFadeDuration
        fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
        layer.add(fade, forKey: Self.focusFadeKey)
    }

    override open func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        applyBackground()
    }

    /// The colour `cardBackground` stands for. Dynamic, so views inside the card can use it as is.
    var resolvedBackgroundColor: NSColor {
        CardColor.resolved(cardBackground)
    }

    private func applyBackground() {
        // The cell itself keeps the window's appearance: only the card's content is switched.
        let isLight = cardBackground.isLight(inDarkMode: effectiveAppearance.isDark)
        contentView.appearance = isLight.map { NSAppearance(named: $0 ? .aqua : .darkAqua) } ?? nil
        contentView.fillColor = resolvedBackgroundColor
    }

    /// An explicit outline spares the compositor from deriving the shadow from the card's pixels
    /// on every frame of a scroll.
    private func updateShadowPath() {
        let outline = isSelected ? selectionView.frame : contentView.frame
        // A rounded-rectangle path may not have corners larger than half its sides.
        let radius = min(
            isSelected ? BaseCellMetrics.selectionCornerRadius : BaseCellMetrics.cornerRadius,
            outline.width / 2,
            outline.height / 2
        )
        layer?.shadowPath = CGPath(roundedRect: outline, cornerWidth: radius, cornerHeight: radius, transform: nil)
    }

    /// The ring while the strip does not have keyboard focus: the accent colour without its hue.
    private static let mutedSelectionColor = NSColor(name: nil) { _ in
        NSColor.controlAccentColor.usingColorSpace(.sRGB)?.usingColorSpace(.genericGray) ?? .gray
    }
}
