import CoreGraphics
import Testing
@testable import PastoStack

@Suite struct StackWindowLayoutTests {
    @Test func theWindowIsThePanelAtItsTallestPlusTheMargins() {
        #expect(StackWindowLayout.windowSize(heightLimit: 400) == CGSize(width: 288, height: 448))
    }

    @Test func aNewHeightLimitKeepsTheTopLeftCornerInPlace() {
        let current = CGRect(x: 268, y: 100, width: 288, height: 300)
        let frame = StackWindowLayout.windowFrame(current: current, heightLimit: 500)
        #expect(frame == CGRect(x: 268, y: -148, width: 288, height: 548))
        #expect(frame.maxY == current.maxY)
    }

    @Test func aWindowWithNoSizeYetGrowsDownFromItsOrigin() {
        let frame = StackWindowLayout.windowFrame(current: CGRect(x: 268, y: 339, width: 0, height: 0), heightLimit: 200)
        #expect(frame == CGRect(x: 268, y: 91, width: 288, height: 248))
    }

    @Test func theHeightLimitFollowsTheScreenUntilTheUserChoosesOne() {
        #expect(StackWindowLayout.heightLimit(stored: 0, visibleScreenHeight: 1055) == 738)
        #expect(StackWindowLayout.heightLimit(stored: 420.5, visibleScreenHeight: 1055) == 420.5)
    }

    @Test func aResizeHasAFloorButNoCeiling() {
        #expect(StackWindowLayout.resizedHeightLimit(90) == 160)
        #expect(StackWindowLayout.resizedHeightLimit(5000) == 5000)
    }

    @Test func theWindowBelongsToTheScreenNearestToItsTop() {
        let screens = [CGRect(x: 0, y: 0, width: 1000, height: 800), CGRect(x: 1000, y: 0, width: 1000, height: 800)]
        let onTheSecond = CGRect(x: 900, y: 300, width: 288, height: 400)
        #expect(StackWindowLayout.screenIndex(forWindowFrame: onTheSecond, screenFrames: screens) == 1)

        // Its top edge is above every screen: the nearest one horizontally wins.
        let above = CGRect(x: 100, y: 700, width: 288, height: 400)
        #expect(StackWindowLayout.screenIndex(forWindowFrame: above, screenFrames: screens) == 0)
        #expect(StackWindowLayout.screenIndex(forWindowFrame: above, screenFrames: []) == nil)
    }

    @Test func aPositionSplitsIntoWholePointsAndTheRestInPixels() {
        let retina = StackWindowLayout.pixelAligned(CGPoint(x: 10.3, y: 10.76), scale: 2)
        #expect(retina.windowOrigin == CGPoint(x: 10, y: 11))
        #expect(retina.contentShift == CGPoint(x: 0.5, y: 0))

        let standard = StackWindowLayout.pixelAligned(CGPoint(x: 10.3, y: -10.6), scale: 1)
        #expect(standard.windowOrigin == CGPoint(x: 10, y: -11))
        #expect(standard.contentShift == .zero)
    }

    @Test func windowServerRectanglesAreFlippedAroundTheMainScreen() {
        let rect = StackWindowLayout.screenRect(fromWindowServer: CGRect(x: 50, y: 100, width: 300, height: 200), mainScreenMaxY: 800)
        #expect(rect == CGRect(x: 50, y: 500, width: 300, height: 200))
    }
}

@Suite struct StackReorderTests {
    /// Three cards of 60 points, 8 apart: their middles are at 30, 98 and 166.
    private let cards = [0, 68, 136].map { CGRect(x: 16, y: $0, width: 208, height: 60) }

    @Test func aRowGoesBelowEveryCardWhoseMiddleIsAboveThePointer() {
        #expect(StackReorder.index(forPointerY: 10, among: cards) == 0)
        #expect(StackReorder.index(forPointerY: 30, among: cards) == 0)
        #expect(StackReorder.index(forPointerY: 31, among: cards) == 1)
        #expect(StackReorder.index(forPointerY: 120, among: cards) == 2)
        #expect(StackReorder.index(forPointerY: 500, among: cards) == 3)
        #expect(StackReorder.index(forPointerY: 500, among: []) == 0)
    }
}
