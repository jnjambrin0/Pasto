import Foundation
@testable import PastoUI
import Testing

/// How a history capacity reads: "3 days", "2 weeks".
struct HistoryCapacityTextTests {
    @Test(arguments: [
        (1, DateComponents(day: 1)),
        (6, DateComponents(day: 6)),
        (7, DateComponents(weekOfMonth: 1)),
        (21, DateComponents(weekOfMonth: 3)),
        (30, DateComponents(month: 1)),
        (330, DateComponents(month: 11)),
        (365, DateComponents(year: 1)),
    ])
    func aCapacityIsWordedInItsLargestWholeUnit(days: Int, components: DateComponents) {
        #expect(HistoryCapacityText.components(forDays: days) == components)
    }

    @Test func longerThanAYearIsCountedInDays() {
        #expect(HistoryCapacityText.components(forDays: 400) == DateComponents(day: 400))
    }

    @Test func noLimitHasNoDuration() {
        #expect(HistoryCapacityText.components(forDays: 0) == nil)
    }

    @Test func aTickIsNamedAfterItsUnit() {
        #expect(HistoryCapacityText.unitName("1 day") == "Day")
        #expect(HistoryCapacityText.unitName("1 semana") == "Semana")
    }

    @Test func onlyTheCountAtTheEndsGoesAndEveryWordIsCapitalised() {
        #expect(HistoryCapacityText.unitName("1 année 1") == "Année")
        #expect(HistoryCapacityText.unitName("1 jour ouvré") == "Jour Ouvré")
        #expect(HistoryCapacityText.unitName("1 day 2 hours") == "Day 2 Hours")
    }

    @Test func everyTickButForeverIsNamedAfterAUnit() {
        #expect(HistoryCapacityText.unitTickLabels.count == HistoryCapacityScale.tickCount - 1)
    }
}
