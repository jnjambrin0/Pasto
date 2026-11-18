import AppKit
import PastoUI
import QuartzCore

/// The wave that hides the strip's cards when suggestions are asked for and reveals the
/// suggestions when they arrive.
///
/// It spreads from the suggestions button: each card fades, and ripples — rises, tilts and
/// settles — after a delay that grows with its distance from the button, weaker the farther it
/// is. Hiding runs at three quarters of the revealing times.
nonisolated enum StripWave {
    struct Timing: Equatable {
        /// After how long the card starts moving.
        var delay: CFTimeInterval
        var fadeDuration: CFTimeInterval
        var rippleDuration: CFTimeInterval
    }

    private typealias Metrics = PicksPanelMetrics

    /// Each centre's distance from `origin` as a fraction of the largest one; the largest is
    /// `emptyExtent` when there are no centres.
    static func relativeDistances(of centers: [CGPoint], from origin: CGPoint, emptyExtent: CGFloat) -> [CGFloat] {
        let distances = centers.map { hypot($0.x - origin.x, $0.y - origin.y) }
        let largest = distances.max() ?? emptyExtent
        guard largest > 0 else { return distances.map { _ in 0 } }
        return distances.map { $0 / largest }
    }

    /// When a card `distance` away (0…1) moves.
    static func timing(distance: CGFloat, reveal: Bool) -> Timing {
        let scale = reveal ? 1 : Metrics.waveHideTimeScale
        return Timing(
            delay: Metrics.waveDelay * CFTimeInterval(distance) * scale,
            fadeDuration: Metrics.waveFadeDuration * scale,
            rippleDuration: Metrics.waveRippleDuration * scale
        )
    }

    /// The four keyframes of the ripple for a card of `size` at `distance` (0…1): rest; a
    /// perspective, then a move along y, a tilt about x and a slight growth; the same perspective
    /// with a smaller opposite move and tilt; rest. Each is made with Core Animation's own calls
    /// on a perspective matrix, so in its row-vector convention it reads `S·R·T·P`. The moves are
    /// about the layer's anchor — AppKit's, the card's bottom-left corner — with nothing to bring
    /// them to its centre.
    static func rippleKeyframes(distance: CGFloat, size: CGSize) -> [CATransform3D] {
        let strength = 1 - Metrics.waveStrengthFalloff * distance
        let height = size.height
        var perspective = CATransform3DIdentity
        if height > 0 {
            perspective.m34 = -1 / (Metrics.wavePerspectiveDepth * height)
        }
        var rise = CATransform3DTranslate(perspective, 0, -Metrics.waveRise * height * strength, 0)
        rise = CATransform3DRotate(rise, Metrics.waveTilt * strength, 1, 0, 0)
        rise = CATransform3DScale(rise, 1 + Metrics.waveSwell * strength, 1 + Metrics.waveSwell * strength, 1)
        var dip = CATransform3DTranslate(perspective, 0, Metrics.waveDip * height * strength, 0)
        dip = CATransform3DRotate(dip, -Metrics.waveCounterTilt * strength, 1, 0, 0)
        return [CATransform3DIdentity, rise, dip, CATransform3DIdentity]
    }
}

extension ItemCollectionView {
    private static let fadeKey = "picksWaveFade"
    private static let rippleKey = "picksWaveRipple"

    /// Hides the cards, or reveals them, with a wave from `origin` (in the strip's coordinates).
    func performWave(from origin: CGPoint, reveal: Bool) {
        isDimmed = !reveal
        let views = waveViews
        let distances = StripWave.relativeDistances(
            of: views.map { convert(NSPoint(x: $0.bounds.midX, y: $0.bounds.midY), from: $0) },
            from: origin,
            emptyExtent: bounds.width
        )
        let reducesMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (view, distance) in zip(views, distances) {
            guard let layer = view.layer else { continue }
            let timing = StripWave.timing(distance: distance, reveal: reveal)
            let start = layer.convertTime(CACurrentMediaTime(), from: nil) + timing.delay
            view.alphaValue = reveal ? 1 : 0

            let fade = CABasicAnimation(keyPath: "opacity")
            fade.fromValue = reveal ? 0 : 1
            fade.toValue = reveal ? 1 : 0
            fade.beginTime = start
            fade.duration = timing.fadeDuration
            fade.fillMode = .backwards
            fade.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.add(fade, forKey: Self.fadeKey)

            guard !reducesMotion else { continue }
            let ripple = CAKeyframeAnimation(keyPath: "transform")
            ripple.values = StripWave.rippleKeyframes(distance: distance, size: view.bounds.size).map { NSValue(caTransform3D: $0) }
            ripple.keyTimes = PicksPanelMetrics.waveKeyTimes
            ripple.timingFunctions = Array(repeating: CAMediaTimingFunction(name: .easeInEaseOut), count: 3)
            ripple.beginTime = start
            ripple.duration = timing.rippleDuration
            ripple.fillMode = .backwards
            layer.add(ripple, forKey: Self.rippleKey)
        }
        CATransaction.commit()
    }

    /// Stops a wave where it is and shows every card.
    func cancelWave() {
        isDimmed = false
        for view in waveViews {
            view.layer?.removeAnimation(forKey: Self.fadeKey)
            view.layer?.removeAnimation(forKey: Self.rippleKey)
            view.alphaValue = 1
        }
    }

    /// The notice cards and the visible item cards.
    private var waveViews: [NSView] {
        (noticeRow?.subviews ?? []) + visibleCellsByIndex.values.map { $0 }
    }
}
