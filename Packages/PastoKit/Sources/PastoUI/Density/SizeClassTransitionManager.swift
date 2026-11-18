import AppKit

/// Blends views from one size class to the next when the panel is resized across a threshold.
public final class SizeClassTransitionManager {
    private static let animationKey = "sizeAnimation"
    private static let duration: TimeInterval = 0.2

    public private(set) var currentSizeClass: SizeClass

    private let animator: Animator
    /// The views to transition, asked for on every frame because cells come and go.
    private let transitionables: () -> [any SizeClassTransitionable]

    public init(sizeClass: SizeClass, hostView: NSView, transitionables: @escaping () -> [any SizeClassTransitionable]) {
        currentSizeClass = sizeClass
        animator = Animator(hostView: hostView)
        self.transitionables = transitionables
    }

    /// Starts a transition if `sizeClass` differs from the current one. The current class
    /// changes immediately; only the views' appearance is animated.
    public func update(to sizeClass: SizeClass) {
        guard sizeClass != currentSizeClass else { return }
        let previous = currentSizeClass
        currentSizeClass = sizeClass
        animator.animate(
            key: Self.animationKey,
            from: CGFloat(0),
            to: 1,
            duration: Self.duration,
            update: { [transitionables] progress in
                for view in transitionables() {
                    view.transition(from: previous, to: sizeClass, progress: progress)
                }
            }
        )
    }
}
