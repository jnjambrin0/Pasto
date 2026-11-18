import CoreGraphics
import Testing
@testable import PastoMainPanel

@Suite struct TabBarReorderTests {
    /// History followed by three pinboards, as laid out: 7…108, 116…216, 224…284 and 292…372,
    /// 28 pt tall from y = 6.
    private let frames = TabBarLayout(cellWidths: [101, 100, 60, 80]).cellFrames

    private func destination(from index: Int, x: CGFloat, y: CGFloat = 20) -> Int {
        TabBarReorder.destinationIndex(cellFrames: frames, currentIndex: index, pointer: CGPoint(x: x, y: y))
    }

    @Test func aTabToTheRightGivesWayOncePassedItsMiddle() {
        // The second tab's gap is at 1; the third spans 224…284, its middle at 254.
        #expect(destination(from: 1, x: 230) == 1)
        #expect(destination(from: 1, x: 254) == 1)
        #expect(destination(from: 1, x: 255) == 2)
    }

    @Test func aTabToTheLeftGivesWayOncePassedItsMiddle() {
        // The last tab's gap is at 3; the second spans 116…216, its middle at 166.
        #expect(destination(from: 3, x: 200) == 2)
        #expect(destination(from: 3, x: 166) == 2)
        #expect(destination(from: 3, x: 165) == 1)
    }

    @Test func aPointerThatJumpsSeveralTabsLandsNextToTheOneUnderIt() {
        // From the history's slot straight onto the last tab, before its middle (332).
        #expect(destination(from: 0, x: 300) == 2)
        #expect(destination(from: 0, x: 340) == 3)
        // And back onto the history's tab, past its middle (57.5).
        #expect(destination(from: 3, x: 80) == 1)
        #expect(destination(from: 3, x: 20) == 0)
    }

    @Test func nothingChangesOverTheGapOrAwayFromTheTabs() {
        // Over the dragged tab's own gap.
        #expect(destination(from: 1, x: 150) == 1)
        // Between two tabs, past the ends, and above or below the strip of tabs.
        #expect(destination(from: 1, x: 220) == 1)
        #expect(destination(from: 1, x: 3) == 1)
        #expect(destination(from: 1, x: 400) == 1)
        #expect(destination(from: 1, x: 254, y: 2) == 1)
        #expect(destination(from: 1, x: 260, y: 36) == 1)
    }

    @Test func movingKeepsTheOtherElementsInOrder() {
        let tabs = ["history", "a", "b", "c"]
        #expect(TabBarReorder.moving(tabs, from: 1, to: 3) == ["history", "b", "c", "a"])
        #expect(TabBarReorder.moving(tabs, from: 3, to: 1) == ["history", "c", "a", "b"])
        #expect(TabBarReorder.moving(tabs, from: 2, to: 2) == tabs)
    }
}
