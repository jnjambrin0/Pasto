import AppKit
import QuartzCore

/// Drives property animations frame by frame from a display link.
///
/// Animations are identified by a key: starting one with a key that is already running replaces
/// it, which is how a scroll or density transition is retargeted mid-flight.
public final class Animator: NSObject {
    /// The engine's default curve.
    public static let defaultTiming = UnitBezier(0.25, 0.1, 0.25, 1.0)

    private struct RunningAnimation {
        let startTime: CFTimeInterval
        let duration: TimeInterval
        let timing: UnitBezier
        let apply: (Double) -> Void
        let completion: ((Bool) -> Void)?
    }

    private weak var hostView: NSView?
    private var displayLink: CADisplayLink?
    private var animations: [String: RunningAnimation] = [:]

    /// The display link follows `hostView`'s screen, so the refresh rate is always the right one.
    public init(hostView: NSView) {
        self.hostView = hostView
    }

    isolated deinit {
        displayLink?.invalidate()
    }

    public func isAnimating(_ key: String) -> Bool {
        animations[key] != nil
    }

    /// Animates from `start` to `end`. `update` receives `start` immediately, then one value per
    /// frame, and finally exactly `end`. `completion` receives false when the animation was
    /// replaced or cancelled.
    ///
    /// - Parameter isMotion: The value moves or resizes something on screen — a scroll, the
    ///   cards sliding into place, a change of density. With Reduce Motion on, such an
    ///   animation goes straight to its end; with it off nothing changes. An animation of
    ///   opacity alone is no motion and keeps its duration.
    public func animate<Value: Interpolatable>(
        key: String,
        from start: Value,
        to end: Value,
        duration: TimeInterval,
        timing: UnitBezier = Animator.defaultTiming,
        isMotion: Bool = true,
        update: @escaping (Value) -> Void,
        completion: ((Bool) -> Void)? = nil
    ) {
        cancel(key)
        let duration = Self.duration(duration, isMotion: isMotion, reducesMotion: Self.reducesMotion)
        // The display link only ticks while the view is on screen, so in a hidden window the
        // animation would never advance: go straight to the end instead.
        guard duration > 0, hostView?.window?.isVisible == true else {
            update(end)
            completion?(true)
            return
        }

        update(start)
        animations[key] = RunningAnimation(
            startTime: CACurrentMediaTime(),
            duration: duration,
            timing: timing,
            apply: { progress in
                update(progress >= 1 ? end : .interpolate(from: start, to: end, progress: progress))
            },
            completion: completion
        )
        startDisplayLinkIfNeeded()
    }

    /// Whether the user asked for less motion (System Settings › Accessibility › Display).
    public static var reducesMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    /// How long an animation lasts: none for a motion while motion is reduced, `duration`
    /// otherwise.
    nonisolated static func duration(_ duration: TimeInterval, isMotion: Bool, reducesMotion: Bool) -> TimeInterval {
        isMotion && reducesMotion ? 0 : duration
    }

    /// Stops an animation where it is. Its completion handler is called with false.
    public func cancel(_ key: String) {
        guard let animation = animations.removeValue(forKey: key) else { return }
        animation.completion?(false)
        stopDisplayLinkIfIdle()
    }

    // MARK: - Display link

    private func startDisplayLinkIfNeeded() {
        guard displayLink == nil, let hostView else { return }
        let link = hostView.displayLink(target: self, selector: #selector(step(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    private func stopDisplayLinkIfIdle() {
        guard animations.isEmpty else { return }
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func step(_ link: CADisplayLink) {
        let now = CACurrentMediaTime()
        var finished: [(String, RunningAnimation)] = []

        for (key, animation) in animations {
            let linearProgress = min(max((now - animation.startTime) / animation.duration, 0), 1)
            animation.apply(linearProgress >= 1 ? 1 : animation.timing.value(at: linearProgress))
            if linearProgress >= 1 {
                finished.append((key, animation))
            }
        }

        for (key, animation) in finished {
            // A callback earlier in this pass may already have replaced the animation.
            guard animations[key]?.startTime == animation.startTime else { continue }
            animations[key] = nil
            animation.completion?(true)
        }
        stopDisplayLinkIfIdle()
    }
}
