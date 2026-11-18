@testable import PastoUI
import Testing

/// The "Keep History" slider's scale: a tick for a day, a week, a month, a year and forever, and
/// the ages in between.
struct HistoryCapacityScaleTests {
    private func days(_ position: Double, isInteractive: Bool = true, previousDays: Int = 30) -> Int {
        HistoryCapacityScale.days(atPosition: position, isInteractive: isInteractive, previousDays: previousDays)
    }

    @Test(arguments: [(1.0, 1), (2.0, 7), (3.0, 30), (4.0, 365), (5.0, 0)])
    func theTicksAreADayAWeekAMonthAYearAndForever(position: Double, days: Int) {
        #expect(self.days(position) == days)
        #expect(self.days(position, isInteractive: false) == days)
        #expect(HistoryCapacityScale.position(forDays: days) == position)
    }

    @Test func theFirstSegmentCountsDays() {
        let days = stride(from: 1.0, to: 2.0, by: 0.01).map { self.days($0) }

        #expect(Set(days) == Set(1...7))
        #expect(days == days.sorted())
    }

    @Test func theSecondSegmentCountsWeeksAndEndsOnAMonth() {
        let days = stride(from: 2.0, to: 3.0, by: 0.01).map { self.days($0) }

        #expect(Set(days) == [7, 14, 21, 30])
        #expect(days == days.sorted())
    }

    @Test func theThirdSegmentCountsMonthsAndEndsOnAYear() {
        let days = stride(from: 3.0, to: 4.0, by: 0.01).map { self.days($0) }

        #expect(Set(days) == Set((1...11).map { $0 * 30 } + [365]))
        #expect(days == days.sorted())
    }

    @Test func underTheMouseBetweenAYearAndForeverTheNearerOneWins() {
        for previousDays in [365, 0, 30] {
            #expect(days(4.1, previousDays: previousDays) == 365)
            #expect(days(4.4, previousDays: previousDays) == 365)
            #expect(days(4.5, previousDays: previousDays) == 0)
            #expect(days(4.9, previousDays: previousDays) == 0)
        }
    }

    @Test func withoutTheMouseAStepOffAYearOrForeverLandsOnTheOtherOne() {
        #expect(days(4.1, isInteractive: false, previousDays: 365) == 0)
        #expect(days(4.9, isInteractive: false, previousDays: 365) == 0)
        #expect(days(4.9, isInteractive: false, previousDays: 0) == 365)
        #expect(days(4.1, isInteractive: false, previousDays: 0) == 365)
    }

    @Test func withoutTheMouseComingFromElsewhereTheNearerOneWins() {
        #expect(days(4.4, isInteractive: false, previousDays: 330) == 365)
        #expect(days(4.5, isInteractive: false, previousDays: 330) == 0)
    }

    @Test func positionsOutsideTheSliderAreItsEnds() {
        #expect(days(0) == 1)
        #expect(days(6) == 0)
    }

    @Test func everyValueTheSliderProducesPutsTheKnobBackWhereItGivesThatValue() {
        let values = Array(1...7) + [14, 21] + (1...11).map { $0 * 30 } + [365, 0]

        for days in values {
            let position = HistoryCapacityScale.position(forDays: days)
            #expect(HistoryCapacityScale.positions.contains(position))
            #expect(self.days(position, previousDays: days) == days)
        }
    }

    @Test func agesTheSliderCannotProduceStillFallInTheirSegment() {
        #expect((2.0..<3.0).contains(HistoryCapacityScale.position(forDays: 10)))
        #expect((3.0..<4.0).contains(HistoryCapacityScale.position(forDays: 100)))
    }

    @Test func longerThanAYearIsOffTheScale() {
        #expect(HistoryCapacityScale.position(forDays: 366) == 0)
        #expect(HistoryCapacityScale.position(forDays: 1_000) == 0)
    }
}
