import AppKit
import PastoUI

/// The bottom of a text card: the text fades out into the card's background, and under the
/// fade an opaque band carries the character count.
///
/// In the compact density the band and the caption go away and only the fade is left.
final class TextFooterView: CardView {
    private enum Metrics {
        static let fadeHeight: CGFloat = 32
        static let bandHeight: CGFloat = 18
        static let bandAnimationKey = "bandHeight"
    }

    /// The card's background, which the text fades into.
    var fadingColor: NSColor = .clear {
        didSet {
            fadingView.colors = .fade(to: fadingColor)
            opaqueView.fillColor = fadingColor
        }
    }

    var caption: String {
        get { captionLabel.stringValue }
        set { captionLabel.stringValue = newValue }
    }

    /// Called while the band's height animates, so the cell can keep the footer at the bottom.
    var onHeightChange: (() -> Void)?

    private let opaqueView = CardView(frame: .zero)
    private let fadingView = GradientEffectView(frame: .zero)
    private let captionLabel = NSTextField.cardLabel(font: .callout, color: .secondary, alignment: .center)

    private var isCompact = false
    private var bandHeight = Metrics.bandHeight
    private var bandAnimator: Animator?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(opaqueView)
        addSubview(fadingView)
        addSubview(captionLabel)
    }

    var height: CGFloat { Metrics.fadeHeight + bandHeight }

    /// Switches between the full footer and the compact one. Animated, the caption fades and
    /// the band collapses or grows.
    func setCompact(_ isCompact: Bool, animated: Bool) {
        guard isCompact != self.isCompact || !animated else { return }
        self.isCompact = isCompact
        let targetHeight = isCompact ? 0 : Metrics.bandHeight

        guard animated else {
            bandAnimator?.cancel(Metrics.bandAnimationKey)
            captionLabel.isHidden = isCompact
            captionLabel.alphaValue = 1
            setBandHeight(targetHeight)
            return
        }

        fadeCaption()
        let animator = bandAnimator ?? Animator(hostView: self)
        bandAnimator = animator
        animator.animate(
            key: Metrics.bandAnimationKey,
            from: bandHeight,
            to: targetHeight,
            duration: CardContentMetrics.fadeDuration,
            timing: .easeOut,
            update: { [weak self] height in self?.setBandHeight(height) }
        )
    }

    /// Fades the caption out and then hides it, or shows it and fades it in.
    private func fadeCaption() {
        if !isCompact {
            captionLabel.isHidden = false
            captionLabel.alphaValue = 0
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = CardContentMetrics.fadeDuration
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            captionLabel.animator().alphaValue = isCompact ? 0 : 1
        } completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // The density may have changed back while the caption was fading.
                guard let self, self.isCompact else { return }
                self.captionLabel.isHidden = true
            }
        }
    }

    private func setBandHeight(_ height: CGFloat) {
        guard height != bandHeight else { return }
        bandHeight = height
        needsLayout = true
        onHeightChange?()
    }

    override func layout() {
        super.layout()
        fadingView.frame = CGRect(x: 0, y: 0, width: bounds.width, height: Metrics.fadeHeight)
        opaqueView.frame = CGRect(x: 0, y: Metrics.fadeHeight, width: bounds.width, height: bandHeight)

        let captionHeight = captionLabel.intrinsicContentSize.height
        captionLabel.setAlignmentRect(CGRect(
            x: 0, y: bounds.height - CardContentMetrics.bottomInset - captionHeight, width: bounds.width, height: captionHeight
        ))
    }
}
