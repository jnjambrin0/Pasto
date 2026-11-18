import CoreGraphics
import Testing
@testable import PastoUI

/// Page Up and Page Down in the strip.
@Suite struct CollectionPagingTests {
    @Test func aPageIsTheCellsThatFitWhole() {
        // Five cells of 100 with 10 between them take 540.
        #expect(CollectionPaging.cellsPerPage(visibleWidth: 540, cellSide: 100, spacing: 10) == 5)
        #expect(CollectionPaging.cellsPerPage(visibleWidth: 539, cellSide: 100, spacing: 10) == 4)
    }

    @Test func aPageIsAtLeastOneCell() {
        #expect(CollectionPaging.cellsPerPage(visibleWidth: 50, cellSide: 100, spacing: 10) == 1)
        #expect(CollectionPaging.cellsPerPage(visibleWidth: 50, cellSide: 0, spacing: 0) == 1)
    }

    @Test func theSelectionStopsAtEitherEnd() {
        #expect(CollectionPaging.index(from: 3, movingBy: 5, cellCount: 20) == 8)
        #expect(CollectionPaging.index(from: 18, movingBy: 5, cellCount: 20) == 19)
        #expect(CollectionPaging.index(from: 2, movingBy: -5, cellCount: 20) == 0)
    }
}
