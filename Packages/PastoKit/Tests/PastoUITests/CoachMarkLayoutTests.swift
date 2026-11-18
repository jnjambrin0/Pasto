import CoreGraphics
@testable import PastoUI
import Testing

/// Where a coach mark goes beside what it explains.
struct CoachMarkLayoutTests {
    /// A panel 1600 × 300 with its 60-point toolbar at the top, y upwards.
    private let panel = CGRect(x: 0, y: 0, width: 1600, height: 300)
    private let size = CGSize(width: 288, height: 110)

    private func place(_ anchor: CGRect, _ sides: [CoachMarkLayout.Side]) -> (frame: CGRect, side: CoachMarkLayout.Side) {
        CoachMarkLayout.frame(size: size, anchor: anchor, in: panel, sides: sides, gap: 8, margin: 12)
    }

    @Test func belowAToolbarButtonCentredOnIt() {
        let search = CGRect(x: 700, y: 254, width: 32, height: 32)

        let placement = place(search, [.below])

        #expect(placement.side == .below)
        #expect(placement.frame == CGRect(x: 572, y: 136, width: 288, height: 110))
    }

    /// The suggestions button sits 16 points from the edge: the mark slides inside the margin.
    @Test func slidesAlongTheSideToStayInside() {
        let suggestions = CGRect(x: 16, y: 254, width: 32, height: 32)
        let more = CGRect(x: 1552, y: 254, width: 32, height: 32)

        #expect(place(suggestions, [.below]).frame.minX == 12)
        #expect(place(more, [.below]).frame.maxX == 1588)
    }

    @Test func besideACardWhenThereIsRoom() {
        let card = CGRect(x: 24, y: 24, width: 232, height: 232)

        let placement = place(card, [.trailing, .leading, .below])

        #expect(placement.side == .trailing)
        #expect(placement.frame == CGRect(x: 264, y: 85, width: 288, height: 110))
    }

    @Test func takesTheNextSideWhenTheFirstHasNoRoom() {
        let lastCard = CGRect(x: 1344, y: 24, width: 232, height: 232)

        let placement = place(lastCard, [.trailing, .leading, .below])

        #expect(placement.side == .leading)
        #expect(placement.frame.maxX == 1336)
    }

    /// No side has room: the first, pushed inside the container.
    @Test func pushedInsideWhenNothingFits() {
        let small = CGRect(x: 0, y: 0, width: 200, height: 120)
        let anchor = CGRect(x: 80, y: 80, width: 32, height: 32)

        let placement = CoachMarkLayout.frame(size: size, anchor: anchor, in: small, sides: [.below], gap: 8, margin: 12)

        #expect(placement.side == .below)
        #expect(placement.frame.minX == 12)
        #expect(placement.frame.minY == 12)
    }
}
