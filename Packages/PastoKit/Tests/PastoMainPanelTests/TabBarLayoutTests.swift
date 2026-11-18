import AppKit
import PastoCore
import Testing
@testable import PastoMainPanel

@Suite struct TabBarLayoutTests {
    // MARK: Cell width

    /// The history tab: 8 + 18 (icon) + 4 + 63 (label) + 8 for a name 58.6 pt wide.
    @Test func historyCellWidth() {
        #expect(TabBarLayout.cellWidth(iconSide: 18, textWidth: 58.64) == 101)
    }

    /// A new pinboard: 8 + 16 (dot) + 4 + 52 (label) + 8 for a name 47.9 pt wide.
    @Test func pinboardCellWidth() {
        #expect(TabBarLayout.cellWidth(iconSide: 16, textWidth: 47.92) == 88)
    }

    @Test func labelIsItsTextRoundedUpPlusTheSlack() {
        #expect(TabBarLayout.labelWidth(textWidth: 48) == 52)
        #expect(TabBarLayout.labelWidth(textWidth: 48.01) == 53)
        #expect(TabBarLayout.labelWidth(textWidth: 0) == 4)
    }

    @Test func labelStopsGrowingAtTheMaximum() {
        #expect(TabBarLayout.labelWidth(textWidth: 196) == 200)
        #expect(TabBarLayout.labelWidth(textWidth: 400) == 200)
        #expect(TabBarLayout.cellWidth(iconSide: 16, textWidth: 400) == 236)
    }

    // MARK: Frames

    /// History plus one pinboard: a scroll area 237 pt wide inside a bar of 239.
    @Test func framesOfTwoTabs() {
        let layout = TabBarLayout(cellWidths: [101, 114])
        #expect(layout.cellFrames == [
            CGRect(x: 7, y: 6, width: 101, height: 28),
            CGRect(x: 116, y: 6, width: 114, height: 28),
        ])
        #expect(layout.contentSize == CGSize(width: 237, height: 40))
        #expect(layout.intrinsicWidth == 239)
    }

    /// Adding the 88 pt tab grows the scroll area from 237 to 333.
    @Test func aThirdTabAddsItsWidthAndTheSpacing() {
        let layout = TabBarLayout(cellWidths: [101, 114, 88])
        #expect(layout.cellFrames[2] == CGRect(x: 238, y: 6, width: 88, height: 28))
        #expect(layout.contentSize.width == 333)
    }

    @Test func emptyBarIsJustItsInsets() {
        let layout = TabBarLayout(cellWidths: [])
        #expect(layout.cellFrames.isEmpty)
        #expect(layout.contentSize == CGSize(width: 14, height: 40))
    }

    // MARK: Scrolling to a tab

    @Test func revealsATabHiddenPastTheTrailingEndWithItsMargin() {
        let layout = TabBarLayout(cellWidths: [101, 114, 88, 100])
        // The third tab ends at 326; with 24 pt to spare the content must show up to 350.
        #expect(layout.scrollOffset(revealing: layout.cellFrames[2], from: 0, visibleWidth: 200) == 150)
    }

    @Test func neverScrollsPastTheEndOfTheContent() {
        let layout = TabBarLayout(cellWidths: [101, 114, 88])
        // The margin would ask for 350, but the content ends at 333.
        #expect(layout.scrollOffset(revealing: layout.cellFrames[2], from: 0, visibleWidth: 200) == 133)
    }

    @Test func revealsATabHiddenBeforeTheLeadingEnd() {
        let layout = TabBarLayout(cellWidths: [101, 114, 88])
        #expect(layout.scrollOffset(revealing: layout.cellFrames[0], from: 133, visibleWidth: 200) == 0)
        // The second tab starts at 116; its margin starts at 92.
        #expect(layout.scrollOffset(revealing: layout.cellFrames[1], from: 133, visibleWidth: 200) == 92)
    }

    @Test func leavesTheOffsetAloneWhenTheTabAndItsMarginsAreVisible() {
        let layout = TabBarLayout(cellWidths: [101, 114, 88])
        // The second tab with its margins spans 92…254.
        #expect(layout.scrollOffset(revealing: layout.cellFrames[1], from: 80, visibleWidth: 200) == 80)
        #expect(layout.scrollOffset(revealing: layout.cellFrames[1], from: 50, visibleWidth: 200) == 54)
    }

    @Test func neverScrollsWhenEverythingFits() {
        let layout = TabBarLayout(cellWidths: [101, 114])
        #expect(layout.scrollOffset(revealing: layout.cellFrames[1], from: 0, visibleWidth: 237) == 0)
        #expect(layout.scrollOffset(revealing: layout.cellFrames[1], from: 40, visibleWidth: 400) == 0)
    }

    @Test func showsTheStartOfATabWiderThanTheVisibleArea() {
        let layout = TabBarLayout(cellWidths: [101, 236, 88])
        // The second tab spans 116…352; only 100 pt are visible.
        #expect(layout.scrollOffset(revealing: layout.cellFrames[1], from: 0, visibleWidth: 100) == 92)
    }

    // MARK: Following a name being typed

    @Test func keepsTheTrailingEdgeOfARenamedTabInView() {
        let layout = TabBarLayout(cellWidths: [101, 114, 88, 100])
        // The last tab ends at 434: the edge is brought just inside, without a margin.
        #expect(layout.scrollOffset(revealingTrailingEdgeOf: layout.cellFrames[3], from: 0, visibleWidth: 200) == 235)
        #expect(layout.scrollOffset(revealingTrailingEdgeOf: layout.cellFrames[3], from: 240, visibleWidth: 200) == 240)
        // Scrolled past it, the edge comes back to the leading side.
        #expect(layout.scrollOffset(revealingTrailingEdgeOf: layout.cellFrames[1], from: 241, visibleWidth: 200) == 230)
    }
}
