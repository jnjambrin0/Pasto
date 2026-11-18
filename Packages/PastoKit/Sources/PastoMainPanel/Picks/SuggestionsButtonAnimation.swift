import AppKit
import QuartzCore

/// How the suggestions button leaves the toolbar when the mode starts and comes back when it
/// ends: it fades while it swells and shrinks away, or grows back with a slight overshoot. The
/// scaling runs only without Reduce Motion.
enum SuggestionsButtonAnimation {
    private typealias Metrics = PicksPanelMetrics
    private static let fadeKey = "picksButtonFade"
    private static let bounceKey = "picksButtonBounce"

    /// Animates `button` into the mode (`isActive`) or out of it; `completion` runs when done.
    static func run(on button: NSView, isActive: Bool, completion: @escaping () -> Void) {
        guard let layer = button.layer else {
            completion()
            return
        }
        CATransaction.begin()
        CATransaction.setCompletionBlock(completion)

        let fade = CABasicAnimation(keyPath: "opacity")
        fade.fromValue = isActive ? 1 : 0
        fade.toValue = isActive ? 0 : 1
        fade.duration = Metrics.buttonAnimationDuration
        button.alphaValue = isActive ? 0 : 1
        layer.add(fade, forKey: fadeKey)

        if !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let bounce = CAKeyframeAnimation(keyPath: "transform")
            let scales = isActive ? Metrics.buttonScalesWhenActivating : Metrics.buttonScalesWhenDeactivating
            bounce.values = scales.map { NSValue(caTransform3D: scale($0, aboutCenterOf: button.bounds.size)) }
            bounce.keyTimes = Metrics.buttonKeyTimes
            bounce.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 2)
            bounce.duration = Metrics.buttonAnimationDuration
            layer.add(bounce, forKey: bounceKey)
        }
        CATransaction.commit()
    }

    /// A uniform scale about the centre of a layer anchored at its corner, as AppKit's are.
    static func scale(_ factor: CGFloat, aboutCenterOf size: CGSize) -> CATransform3D {
        let center = CATransform3DMakeTranslation(size.width / 2, size.height / 2, 0)
        return [CATransform3DMakeScale(factor, factor, 1), center]
            .reduce(CATransform3DMakeTranslation(-size.width / 2, -size.height / 2, 0), CATransform3DConcat)
    }
}
