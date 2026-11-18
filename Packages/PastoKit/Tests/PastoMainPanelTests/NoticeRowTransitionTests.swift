import CoreGraphics
import PastoUI
import Testing
@testable import PastoMainPanel

/// How the notice cards move when the set of cards changes.
@Suite struct NoticeRowTransitionTests {
    private typealias Transition = NoticeRowTransition<String>
    private let side: CGFloat = 232

    private func settled(_ index: Int) -> Transition.CardState {
        let frame = NoticeCardMetrics.cardFrame(at: index, cellSide: side)
        return Transition.CardState(frame: frame, alpha: 1, visibleWidth: frame.width)
    }

    @Test func anArrivingCardGrowsIntoItsPlaceAndTheRowWidens() {
        let transition = Transition(current: [:], currentWidth: 0, order: ["a"], cellSide: side)

        let start = transition.state(of: "a", at: 0)
        #expect(start == Transition.CardState(frame: settled(0).frame, alpha: 0, visibleWidth: 0))
        #expect(transition.state(of: "a", at: 1) == settled(0))
        #expect(transition.width(at: 0) == 0)
        #expect(transition.width(at: 1) == 224)
        #expect(transition.departing.isEmpty)
    }

    @Test func aLeavingCardShrinksWhereItIsWhileTheOthersMoveUp() {
        let current = ["a": settled(0), "b": settled(1)]
        let transition = Transition(current: current, currentWidth: 448, order: ["b"], cellSide: side)

        #expect(transition.departing == ["a"])
        #expect(transition.state(of: "a", at: 1) == Transition.CardState(frame: settled(0).frame, alpha: 0, visibleWidth: 0))
        #expect(transition.state(of: "b", at: 0) == settled(1))
        #expect(transition.state(of: "b", at: 1) == settled(0))
        let halfway = transition.state(of: "b", at: 0.5)
        #expect(halfway?.frame.minX == (settled(0).frame.minX + settled(1).frame.minX) / 2)
        #expect(transition.width(at: 1) == 224)
    }

    /// A transition that replaces one under way starts from what is on show, and a card that was
    /// leaving and comes back fades in again from where it had got to.
    @Test func anInterruptedTransitionStartsFromWhatIsOnShow() {
        let fading = Transition.CardState(frame: settled(0).frame, alpha: 0.4, visibleWidth: 80)
        let transition = Transition(current: ["a": fading], currentWidth: 100, order: ["a"], cellSide: side)

        #expect(transition.state(of: "a", at: 0) == fading)
        #expect(transition.state(of: "a", at: 1) == settled(0))
        #expect(transition.width(at: 0) == 100)
        #expect(transition.departing.isEmpty)
    }
}
