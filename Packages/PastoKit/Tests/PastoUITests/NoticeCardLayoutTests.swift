import CoreGraphics
@testable import PastoUI
import Testing

/// The layout of a notice card and of the row of cards before the strip's first item.
struct NoticeCardLayoutTests {
    // MARK: Row of cards

    @Test func aCardIsAsTallAsAnItemCardAndAtMostTwoHundredPointsWide() {
        #expect(NoticeCardMetrics.cardSize(cellSide: 232) == CGSize(width: 200, height: 232))
        #expect(NoticeCardMetrics.cardSize(cellSide: 160) == CGSize(width: 160, height: 160))
        #expect(NoticeCardMetrics.cardSize(cellSide: 40) == CGSize(width: 80, height: 80))
    }

    @Test func theRowTakesItsCardsTheGapsBetweenThemAndTheLeadingMargin() {
        #expect(NoticeCardMetrics.rowWidth(cardCount: 0, cellSide: 232) == 0)
        #expect(NoticeCardMetrics.rowWidth(cardCount: 1, cellSide: 232) == 224)
        #expect(NoticeCardMetrics.rowWidth(cardCount: 3, cellSide: 232) == 672)
    }

    // MARK: Card

    private func layout(_ sizeClass: SizeClass, height: CGFloat = 232, descriptionHeight: CGFloat = 40) -> NoticeCardLayout {
        NoticeCardLayout(
            size: CGSize(width: 200, height: height),
            metrics: NoticeCardMetrics(sizeClass: sizeClass),
            titleHeight: 20,
            descriptionHeight: descriptionHeight,
            buttonHeight: 24
        )
    }

    @Test func theIconSitsInTheTopLeadingCornerAndTheTextUnderIt() {
        let layout = layout(.regular)

        #expect(layout.icon == CGRect(x: 12, y: 12, width: 28, height: 28))
        #expect(layout.title == CGRect(x: 12, y: 48, width: 172, height: 20))
        #expect(layout.description == CGRect(x: 12, y: 72, width: 172, height: 40))
    }

    @Test func theCompactDensityTightensTheIconAndItsGap() {
        let layout = layout(.compact, height: 180)

        #expect(layout.icon == CGRect(x: 10, y: 10, width: 20, height: 20))
        #expect(layout.title.minY == 34)
    }

    @Test func theButtonSpansTheBottomOfTheCard() {
        #expect(layout(.regular).button == CGRect(x: 12, y: 196, width: 176, height: 24))
    }

    @Test func textThatDoesNotFitAboveTheButtonIsCutShort() {
        let layout = layout(.regular, height: 110, descriptionHeight: 80)

        #expect(layout.button.minY == 74)
        #expect(layout.title.maxY <= layout.button.minY)
        #expect(layout.description.height == 0)
    }
}
