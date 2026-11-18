import CoreGraphics
import Testing
@testable import PastoUI

/// Autoscroll while cards are dragged to reorder them: a 30 pt band at either end, up to 15 pt
/// per update.
@Suite struct DraggingAutoscrollTests {
    private func step(at x: CGFloat) -> CGFloat {
        CollectionView.autoscrollStep(pointerX: x, from: 100, to: 900)
    }

    @Test func nothingAwayFromTheEnds() {
        #expect(step(at: 130) == 0)
        #expect(step(at: 500) == 0)
        #expect(step(at: 870) == 0)
    }

    @Test func backwardsNearTheLeadingEndFasterTheCloser() {
        #expect(step(at: 115) == -7.5)
        #expect(step(at: 100) == -15)
    }

    @Test func forwardsNearTheTrailingEndFasterTheCloser() {
        #expect(step(at: 885) == 7.5)
        #expect(step(at: 900) == 15)
    }

    @Test func pastAnEndIsAsFastAsItGets() {
        #expect(step(at: 40) == -15)
        #expect(step(at: 960) == 15)
    }
}
