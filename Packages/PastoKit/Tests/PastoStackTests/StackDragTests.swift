import CoreGraphics
import Foundation
import Testing
@testable import PastoStack

/// A panel of 240 × 200 at (500, 300) on a screen of 1000 × 800, grabbed 100 points in from its
/// bottom-left corner. Its right edge starts at 740; the screen's is at 1000, where the panel's
/// origin would be 760.
@Suite struct StackDragTests {
    private static let screen = CGRect(x: 0, y: 0, width: 1000, height: 800)
    private static let panel = CGRect(x: 500, y: 300, width: 240, height: 200)
    /// One display frame.
    private static let frame: TimeInterval = 1.0 / 60

    private var drag: StackDrag
    private var pointer = CGPoint(x: 600, y: 400)
    private var time: TimeInterval = 0

    init() {
        drag = Self.makeDrag(guides: SnapGuideBuilder.guides(screens: [Self.screen], windows: [], ownWindowNumber: 0))
    }

    private static func makeDrag(panel: CGRect = panel, guides: [SnapGuide]) -> StackDrag {
        StackDrag(pointer: CGPoint(x: panel.minX + 100, y: panel.minY + 100), time: 0, panelFrame: panel, guides: guides)
    }

    /// Moves the pointer by `step` once per frame, `count` times, and returns the last origin.
    @discardableResult
    private mutating func move(by step: CGVector, times count: Int = 1, isSnappingOn: Bool = true) -> CGPoint {
        var origin = drag.origin
        for _ in 0..<count {
            pointer.x += step.dx
            pointer.y += step.dy
            time += Self.frame
            origin = drag.moved(pointer: pointer, time: time, isSnappingOn: isSnappingOn)
        }
        return origin
    }

    // MARK: - Free movement

    @Test mutating func thePanelFollowsThePointerAwayFromAnyGuide() {
        #expect(move(by: CGVector(dx: 3, dy: -2), times: 10) == CGPoint(x: 530, y: 280))
    }

    // MARK: - Catching

    @Test mutating func aSlowEdgeCatchesOnTheScreenEdgeItCrosses() {
        // 2 points per frame is 120 points per second.
        let origin = move(by: CGVector(dx: 2, dy: 0), times: 135)
        #expect(origin == CGPoint(x: 760, y: 300))
    }

    @Test mutating func aFastEdgeGoesStraightThrough() {
        // 20 points per frame is 1200 points per second.
        let origin = move(by: CGVector(dx: 20, dy: 0), times: 14)
        #expect(origin.x == 780)
    }

    @Test mutating func holdingOptionSwitchesSnappingOff() {
        let origin = move(by: CGVector(dx: 2, dy: 0), times: 135, isSnappingOn: false)
        #expect(origin.x == 770)
    }

    @Test mutating func aScreenEdgeDoesNotCatchAPanelComingBackIn() {
        move(by: CGVector(dx: 20, dy: 0), times: 14)
        let origin = move(by: CGVector(dx: -2, dy: 0), times: 15)
        #expect(origin.x == 750)
    }

    // MARK: - Letting go

    @Test mutating func aHeldEdgeGivesWayToAShortPullStraightOn() {
        move(by: CGVector(dx: 2, dy: 0), times: 131)
        #expect(drag.origin.x == 760)

        // The pointer is 2 points past the catch; 16 more frames make it 34.
        #expect(move(by: CGVector(dx: 2, dy: 0), times: 16).x == 760)
        // At 36 the edge comes off, and the panel carries on from the line without a jump.
        #expect(move(by: CGVector(dx: 2, dy: 0)).x == 760)
        #expect(move(by: CGVector(dx: 2, dy: 0)).x == 762)
    }

    @Test mutating func aHeldEdgeComesOffAtOnceWhenPulledBackTheWayItCame() {
        move(by: CGVector(dx: 2, dy: 0), times: 131)
        // Back across the line: released on that step, moving from the next one.
        #expect(move(by: CGVector(dx: -4, dy: 0)).x == 760)
        #expect(move(by: CGVector(dx: -4, dy: 0)).x == 756)
    }

    @Test mutating func slidingAlongTheLineTakesAMuchLongerPull() {
        // A screen tall enough for its right edge to be the only guide in reach.
        let tallScreen = CGRect(x: 0, y: -5000, width: 1000, height: 10000)
        drag = Self.makeDrag(guides: SnapGuideBuilder.guides(screens: [tallScreen], windows: [], ownWindowNumber: 0))
        move(by: CGVector(dx: 2, dy: 0), times: 131)

        // Mostly downwards: about 76° away from the horizontal axis.
        let origin = move(by: CGVector(dx: 1, dy: -4), times: 100)
        #expect(origin == CGPoint(x: 760, y: -100))

        // 140 points of pull are reached 38 frames later.
        #expect(move(by: CGVector(dx: 1, dy: -4), times: 37).x == 760)
        move(by: CGVector(dx: 1, dy: -4), times: 2)
        #expect(drag.origin.x == 761)
    }

    @Test mutating func axesAreIndependent() {
        // Diagonal towards the right edge: the horizontal axis catches, the vertical one goes on.
        let origin = move(by: CGVector(dx: 2, dy: 1), times: 135)
        #expect(origin == CGPoint(x: 760, y: 435))
    }

    // MARK: - Windows

    /// A drag whose only guides are the edges of a window to the right of the panel, with its
    /// left edge at 900.
    private mutating func placeWindow(y: CGFloat) {
        let window = SnapWindow(frame: CGRect(x: 900, y: y, width: 300, height: 400), layer: 0, alpha: 1, number: 7)
        drag = Self.makeDrag(guides: SnapGuideBuilder.guides(screens: [], windows: [window], ownWindowNumber: 0))
    }

    @Test mutating func thePanelRestsNextToAWindowWithAGap() {
        placeWindow(y: 200)
        // Right edge at 899: one point short of the window.
        #expect(move(by: CGVector(dx: 2, dy: 0), times: 85).x == 659)
    }

    @Test mutating func aWindowEdgeOnlyCatchesAlongItsVisibleStretch() {
        // Well above the panel: their vertical extents do not meet.
        placeWindow(y: 600)
        #expect(move(by: CGVector(dx: 2, dy: 0), times: 85).x == 670)
    }

    @Test mutating func aFreedEdgeDoesNotCatchAgainAtOnce() {
        placeWindow(y: 200)
        move(by: CGVector(dx: 2, dy: 0), times: 81)
        #expect(drag.origin.x == 659)

        // Option frees the edge, which is still on the line when Option is let go.
        move(by: CGVector(dx: 2, dy: 0), isSnappingOn: false)
        #expect(drag.origin.x == 659)
        #expect(move(by: CGVector(dx: 2, dy: 0)).x == 661)
    }

    // MARK: - Starting on a guide

    @Test mutating func aPanelLeftOnAGuideStartsHeld() {
        let panel = CGRect(x: 760, y: 300, width: 240, height: 200)
        drag = Self.makeDrag(
            panel: panel,
            guides: SnapGuideBuilder.guides(screens: [Self.screen], windows: [], ownWindowNumber: 0)
        )
        pointer = CGPoint(x: 860, y: 400)
        // A pull of 20 points towards the outside is not enough to take it off the edge.
        #expect(move(by: CGVector(dx: 2, dy: 0), times: 10).x == 760)
    }
}
