import AppKit
import PastoUI

/// The row of notice cards that leads the item strip and scrolls with it. The strip tells it how
/// tall a card is, gives it the frame it asks for and starts its items where the row ends.
///
/// When cards arrive, leave or change places the row moves them over 0.35 s with the
/// `Animator` — frame, opacity and a mask per card — and the width it asks for travels with
/// them, so the strip's items follow frame by frame. It also takes part in the strip's density
/// transition.
final class NoticeRowView: NSView, SizeClassTransitionable {
    private typealias Transition = NoticeRowTransition<NoticeCard.ID>

    private static let transitionAnimationKey = "transitionAnimation"

    var onAction: ((NoticeCard.Command) -> Void)?
    var onClose: ((NoticeCard.ID) -> Void)?
    /// The room the row needs has changed; during a transition, on every frame.
    var onSizeChange: (() -> Void)?

    /// The cards on show, in order.
    var cards: [NoticeCard] = [] {
        didSet {
            guard cards != oldValue else { return }
            updateCardViews(previousCount: oldValue.count)
        }
    }

    /// The side of an item card, which the notice cards follow. The row works out its own
    /// density from it, with the strip's thresholds.
    var cellSide: CGFloat = 0 {
        didSet {
            guard cellSide != oldValue else { return }
            needsLayout = true
            if SizeClass(cellSide: cellSide) != SizeClass(cellSide: oldValue) { configureCardViews() }
        }
    }

    private struct Entry {
        let view: NoticeCardView
        /// What it shows now; kept up to date during a transition, which starts from it.
        var state: Transition.CardState
    }

    private let closeButtonLabel: String
    /// The card views on show, those still leaving included.
    private var entries: [NoticeCard.ID: Entry] = [:]
    /// The width the row takes while a transition runs; nil the rest of the time.
    private var transitionWidth: CGFloat?
    private lazy var animator = Animator(hostView: self)

    /// - Parameter closeButtonLabel: The name of a card's close button for assistive technologies.
    init(closeButtonLabel: String) {
        self.closeButtonLabel = closeButtonLabel
        super.init(frame: .zero)
        // A card that leaves keeps fading where it was while the row shrinks under it.
        clipsToBounds = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoticeRowView is created in code")
    }

    /// The room the row takes from the strip; none without cards.
    var rowSize: CGSize {
        CGSize(
            width: transitionWidth ?? NoticeCardMetrics.rowWidth(cardCount: cards.count, cellSide: cellSide),
            height: NoticeCardMetrics.cardSize(cellSide: cellSide).height
        )
    }

    /// While a transition runs, the transition places the cards.
    override func layout() {
        super.layout()
        guard transitionWidth == nil else { return }
        for (index, card) in cards.enumerated() {
            guard var entry = entries[card.id] else { continue }
            let frame = NoticeCardMetrics.cardFrame(at: index, cellSide: cellSide)
            entry.view.frame = frame
            entry.state = Transition.CardState(frame: frame, alpha: 1, visibleWidth: frame.width)
            entries[card.id] = entry
        }
    }

    // MARK: - Density

    func transition(from source: SizeClass, to destination: SizeClass, progress: Double) {
        for entry in entries.values {
            entry.view.transition(from: source, to: destination, progress: progress)
        }
    }

    // MARK: - Cards

    /// Keeps the view of every card that stays, makes views for the new ones and moves them all
    /// to the new row.
    private func updateCardViews(previousCount: Int) {
        // What is on show now, which the transition starts from; a new card is not, and starts
        // hidden in its place.
        let current = entries.mapValues(\.state)
        for card in cards where entries[card.id] == nil {
            let view = NoticeCardView(closeButtonLabel: closeButtonLabel)
            view.onAction = { [weak self] in self?.onAction?($0) }
            let id = card.id
            view.onClose = { [weak self] in self?.onClose?(id) }
            addSubview(view)
            entries[card.id] = Entry(view: view, state: Transition.CardState(frame: .zero, alpha: 0, visibleWidth: 0))
        }
        configureCardViews()

        let transition = Transition(
            current: current,
            currentWidth: transitionWidth ?? NoticeCardMetrics.rowWidth(cardCount: previousCount, cellSide: cellSide),
            order: cards.map(\.id),
            cellSide: cellSide
        )
        run(transition)
    }

    private func configureCardViews() {
        let sizeClass = SizeClass(cellSide: cellSide)
        for card in cards {
            entries[card.id]?.view.configure(with: card, sizeClass: sizeClass)
        }
    }

    private func run(_ transition: Transition) {
        // Without anything to see — the row hidden, as over a pinboard, or not laid out yet —
        // the cards go straight to their places.
        let isVisible = !isHiddenOrHasHiddenAncestor && cellSide > 0
        animator.animate(
            key: Self.transitionAnimationKey,
            from: CGFloat(0),
            to: 1,
            duration: isVisible ? NoticeCardMetrics.transitionDuration : 0,
            update: { [weak self] progress in self?.show(transition, at: progress) },
            completion: { [weak self] finished in
                if finished { self?.finish(transition) }
            }
        )
    }

    private func show(_ transition: Transition, at progress: CGFloat) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for (id, var entry) in entries {
            guard let state = transition.state(of: id, at: progress) else { continue }
            entry.state = state
            entries[id] = entry
            entry.view.frame = state.frame
            entry.view.alphaValue = state.alpha
            mask(of: entry.view).frame = CGRect(x: 0, y: 0, width: state.visibleWidth, height: state.frame.height)
        }
        CATransaction.commit()
        transitionWidth = transition.width(at: progress)
        onSizeChange?()
    }

    private func finish(_ transition: Transition) {
        for id in transition.departing {
            entries.removeValue(forKey: id)?.view.removeFromSuperview()
        }
        for entry in entries.values {
            entry.view.layer?.mask = nil
        }
        transitionWidth = nil
        needsLayout = true
        onSizeChange?()
    }

    /// The layer that shows only part of a card during a transition.
    private func mask(of view: NoticeCardView) -> CALayer {
        if let mask = view.layer?.mask { return mask }
        let mask = CALayer()
        mask.backgroundColor = CGColor.black
        view.layer?.mask = mask
        return mask
    }
}
