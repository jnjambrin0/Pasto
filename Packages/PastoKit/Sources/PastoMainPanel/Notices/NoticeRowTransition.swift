import CoreGraphics
import PastoUI

/// How the notice cards move when the set of cards changes: every card goes from where it is
/// shown now to its place in the new row, a card that arrives grows into its place from its
/// leading edge while it fades in, and one that leaves shrinks towards its leading edge where it
/// is while it fades out. The row's width travels with them, and the strip's items with it.
nonisolated struct NoticeRowTransition<ID: Hashable>: Equatable {
    /// What is shown of one card at a moment of the transition.
    nonisolated struct CardState: Equatable, Interpolatable {
        /// In the row's coordinates.
        var frame: CGRect
        var alpha: CGFloat
        /// How much of the card shows, from its leading edge: 0 hides it, its width shows all.
        var visibleWidth: CGFloat

        nonisolated static func interpolate(from start: CardState, to end: CardState, progress: Double) -> CardState {
            CardState(
                frame: .interpolate(from: start.frame, to: end.frame, progress: progress),
                alpha: .interpolate(from: start.alpha, to: end.alpha, progress: progress),
                visibleWidth: .interpolate(from: start.visibleWidth, to: end.visibleWidth, progress: progress)
            )
        }
    }

    nonisolated struct Path: Equatable {
        var start: CardState
        var end: CardState
    }

    /// Every card on show at either end, those leaving included.
    let paths: [ID: Path]
    /// The cards that are not in the new row, to be dropped at the end.
    let departing: Set<ID>
    let startWidth: CGFloat
    let endWidth: CGFloat

    /// - Parameters:
    ///   - current: What each card on show looks like now, including cards still leaving from an
    ///     earlier transition.
    ///   - currentWidth: The width the row takes now.
    ///   - order: The cards of the new row, in order.
    ///   - cellSide: The side of an item card, which the notice cards follow.
    init(current: [ID: CardState], currentWidth: CGFloat, order: [ID], cellSide: CGFloat) {
        var paths: [ID: Path] = [:]
        for (index, id) in order.enumerated() {
            let frame = NoticeCardMetrics.cardFrame(at: index, cellSide: cellSide)
            let end = CardState(frame: frame, alpha: 1, visibleWidth: frame.width)
            paths[id] = Path(start: current[id] ?? CardState(frame: frame, alpha: 0, visibleWidth: 0), end: end)
        }
        var departing = Set<ID>()
        for (id, state) in current where paths[id] == nil {
            departing.insert(id)
            paths[id] = Path(start: state, end: CardState(frame: state.frame, alpha: 0, visibleWidth: 0))
        }
        self.paths = paths
        self.departing = departing
        startWidth = currentWidth
        endWidth = NoticeCardMetrics.rowWidth(cardCount: order.count, cellSide: cellSide)
    }

    func state(of id: ID, at progress: Double) -> CardState? {
        paths[id].map { .interpolate(from: $0.start, to: $0.end, progress: progress) }
    }

    func width(at progress: Double) -> CGFloat {
        .interpolate(from: startWidth, to: endWidth, progress: progress)
    }
}
