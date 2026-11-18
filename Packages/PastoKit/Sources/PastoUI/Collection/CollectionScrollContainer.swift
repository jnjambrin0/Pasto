import AppKit
import QuartzCore

/// Wraps the strip's scroll view: reports scrolling, and performs programmatic scrolling timed
/// by how quickly the requests follow one another.
final class CollectionScrollContainer: NSView {
    private enum Metrics {
        /// A programmatic scroll lasts as long as the time since the previous one, up to this cap…
        static let maximumScrollDuration: TimeInterval = 0.25
        /// …and requests closer together than this jump without animating, so holding an arrow
        /// key keeps up with key repeat.
        static let immediateScrollInterval: TimeInterval = 0.1
        static let scrollAnimationKey = "contentOffset"
    }

    var onScroll: (() -> Void)?
    let documentView = NSView(frame: .zero)

    private let scrollView = NoShiftHorizontalScrollView(frame: .zero)
    private lazy var scrollAnimator = Animator(hostView: self)
    private var lastScrollTimestamp: CFTimeInterval = 0
    private var silencesScrollEvents = false
    private var observers: [any NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        scrollView.documentView = documentView
        scrollView.autoresizingMask = [.width, .height]
        addSubview(scrollView)

        let center = NotificationCenter.default
        clipView.postsBoundsChangedNotifications = true
        observers.append(center.addObserver(
            forName: NSView.boundsDidChangeNotification, object: clipView, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.silencesScrollEvents else { return }
                self.onScroll?()
            }
        })
        // A scroll gesture by the user takes over from any programmatic scroll in progress.
        observers.append(center.addObserver(
            forName: NSScrollView.willStartLiveScrollNotification, object: scrollView, queue: nil
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.scrollAnimator.cancel(Metrics.scrollAnimationKey)
            }
        })
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("CollectionScrollContainer is created in code")
    }

    isolated deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    private var clipView: NSClipView { scrollView.contentView }

    var contentOffset: CGPoint { clipView.bounds.origin }

    /// The part of the document currently shown.
    var visibleDocumentRect: CGRect {
        CGRect(origin: clipView.bounds.origin, size: frame.size)
    }

    /// The horizontal offsets the clip view lets the content take: from its start to where its
    /// end meets the trailing edge.
    var horizontalOffsetRange: ClosedRange<CGFloat> {
        0...max(documentView.frame.width - frame.width, 0)
    }

    /// Moves the content without notifying `onScroll`, for adjustments made during layout.
    func setContentOffsetSilently(_ offset: CGPoint) {
        performWithoutScrollEvents { apply(offset) }
    }

    /// Runs `body` without notifying `onScroll` of any scrolling it causes.
    func performWithoutScrollEvents(_ body: () -> Void) {
        let wasSilencing = silencesScrollEvents
        silencesScrollEvents = true
        body()
        silencesScrollEvents = wasSilencing
    }

    /// `completion` receives false when another scroll replaced this one before it arrived.
    func setContentOffset(_ offset: CGPoint, animated: Bool, completion: ((_ finished: Bool) -> Void)? = nil) {
        guard offset != contentOffset else {
            completion?(true)
            return
        }
        guard animated else {
            scrollAnimator.cancel(Metrics.scrollAnimationKey)
            apply(offset)
            completion?(true)
            return
        }

        let now = CACurrentMediaTime()
        let elapsed = min(now - lastScrollTimestamp, Metrics.maximumScrollDuration)
        lastScrollTimestamp = now
        scrollAnimator.animate(
            key: Metrics.scrollAnimationKey,
            from: contentOffset,
            to: offset,
            duration: elapsed <= Metrics.immediateScrollInterval ? 0 : elapsed,
            update: { [weak self] in self?.apply($0) },
            completion: completion
        )
    }

    private func apply(_ offset: CGPoint) {
        clipView.setBoundsOrigin(offset)
        scrollView.reflectScrolledClipView(clipView)
    }
}
