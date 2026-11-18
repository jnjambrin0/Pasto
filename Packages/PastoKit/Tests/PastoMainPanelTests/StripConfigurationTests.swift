import CoreGraphics
import PastoUI
import Testing
@testable import PastoMainPanel

/// Where the strip's first item starts, with and without notice cards before it.
@Suite struct StripConfigurationTests {
    /// The strip of a panel at its default height: 264 pt tall, cards 232 pt a side.
    private func firstItemFrame(noticeCount: Int) -> CGRect {
        let rowWidth = NoticeCardMetrics.rowWidth(cardCount: noticeCount, cellSide: 232)
        let layout = CollectionContentLayout(
            configuration: MainPanelMetrics.stripConfiguration(leadingContentWidth: rowWidth),
            boundsSize: CGSize(width: 1712, height: 264),
            cellCount: 1
        )
        return layout.frame(forCellAt: 0)
    }

    @Test func withoutNoticesTheFirstItemStartsAtTheSideInset() {
        #expect(firstItemFrame(noticeCount: 0) == CGRect(x: 24, y: 24, width: 232, height: 232))
    }

    /// The notice takes x 24…224 and the first item starts 24 pt after it.
    @Test func oneNoticePushesTheFirstItemPastIt() {
        #expect(NoticeCardMetrics.cardFrame(at: 0, cellSide: 232) == CGRect(x: 24, y: 0, width: 200, height: 232))
        #expect(firstItemFrame(noticeCount: 1).minX == 248)
    }

    @Test func everyFurtherNoticeTakesItsWidthAndTheGap() {
        #expect(NoticeCardMetrics.cardFrame(at: 1, cellSide: 232).minX == 248)
        #expect(firstItemFrame(noticeCount: 2).minX == 472)
    }

    /// Below 200 pt a notice is as wide as it is tall.
    @Test func noticesNarrowWithTheCardsInACompactPanel() {
        #expect(NoticeCardMetrics.cardFrame(at: 1, cellSide: 152) == CGRect(x: 200, y: 0, width: 152, height: 152))
    }
}
