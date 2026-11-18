import CoreGraphics
import Testing
@testable import PastoUI

@Suite struct CollectionContentLayoutTests {
    /// The item strip's configuration with no notification cards: 8 above, 24 below and at the sides.
    static let configuration = CollectionContentLayout.Configuration(top: 8, left: 24, bottom: 24, right: 24, interitemSpacing: 24)

    func layout(height: CGFloat = 264, width: CGFloat = 1712, cells: Int = 50) -> CollectionContentLayout {
        CollectionContentLayout(configuration: Self.configuration, boundsSize: CGSize(width: width, height: height), cellCount: cells)
    }

    @Test func cellsAreSquareAndFollowTheHeight() {
        #expect(layout(height: 264).cellSide == 232)
        #expect(layout(height: 184).cellSide == 152)
        #expect(layout(height: 344).cellSide == 312)
        #expect(layout(height: 10).cellSide == 0)
    }

    @Test func cellFrames() {
        let layout = layout()
        #expect(layout.frame(forCellAt: 0) == CGRect(x: 24, y: 24, width: 232, height: 232))
        #expect(layout.frame(forCellAt: 3) == CGRect(x: 24 + 3 * 256, y: 24, width: 232, height: 232))
    }

    @Test func documentIsNeverSmallerThanTheCollection() {
        #expect(layout(cells: 0).documentSize == CGSize(width: 1712, height: 264))
        #expect(layout(cells: 3).documentSize == CGSize(width: 1712, height: 264))
        // 24 + 50 cells of 232 + 49 gaps of 24 + 24
        #expect(layout(cells: 50).contentWidth == CGFloat(12824))
        #expect(layout(cells: 50).documentSize == CGSize(width: 12824, height: 264))
    }

    @Test func visibleIndexesHaveNoPreloadMargin() {
        let layout = layout()
        // At rest: cells 0…6 (cell 6 starts at 1560 and is cut by the right edge).
        #expect(layout.visibleIndexes(in: CGRect(x: 0, y: 0, width: 1712, height: 264)) == 0...6)
        // A cell stays alive while the gap after it is still inside the rectangle.
        #expect(layout.visibleIndexes(in: CGRect(x: 24 + 255, y: 0, width: 100, height: 264)) == 0...1)
        #expect(layout.visibleIndexes(in: CGRect(x: 24 + 256, y: 0, width: 100, height: 264)) == 1...1)
    }

    @Test func visibleIndexesAreClamped() {
        #expect(layout(cells: 3).visibleIndexes(in: CGRect(x: 0, y: 0, width: 1712, height: 264)) == 0...2)
        #expect(layout(cells: 3).visibleIndexes(in: CGRect(x: 5000, y: 0, width: 100, height: 264)) == 2...2)
        #expect(layout(cells: 0).visibleIndexes(in: CGRect(x: 0, y: 0, width: 1712, height: 264)) == nil)
        #expect(layout().visibleIndexes(in: .zero) == nil)
    }

    @Test func hitTesting() {
        let layout = layout(cells: 5)
        #expect(layout.index(at: CGPoint(x: 24, y: 24)) == 0)
        #expect(layout.index(at: CGPoint(x: 255.9, y: 255.9)) == 0)
        #expect(layout.index(at: CGPoint(x: 260, y: 100)) == nil)  // gap
        #expect(layout.index(at: CGPoint(x: 280, y: 100)) == 1)
        #expect(layout.index(at: CGPoint(x: 10, y: 100)) == nil)  // left inset
        #expect(layout.index(at: CGPoint(x: 280, y: 10)) == nil)  // below the row
        #expect(layout.index(at: CGPoint(x: 280, y: 260)) == nil)  // above the row
        #expect(layout.index(at: CGPoint(x: 3000, y: 100)) == nil)  // past the end
    }
}
