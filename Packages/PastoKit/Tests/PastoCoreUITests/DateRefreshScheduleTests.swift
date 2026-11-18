import Foundation
@testable import PastoCoreUI
import Testing

/// A card's date pauses while the panel is closed and, when it opens, reads what it would have
/// read had it refreshed every 30 s all along.
struct DateRefreshScheduleTests {
    private let due = Date(timeIntervalSinceReferenceDate: 1_000)

    @Test func beforeItIsDueNothingIsMissed() {
        let resumption = DateRefreshSchedule.resume(due: due, now: due.addingTimeInterval(-12))
        #expect(resumption.textDate == nil)
        #expect(resumption.nextDue == due)
    }

    @Test func theTextIsThatOfTheLastRefreshMissedAndTheNextFollowsIt() {
        // Due at 1000; refreshes would have come at 1000, 1030, 1060; opened at 1075.
        let resumption = DateRefreshSchedule.resume(due: due, now: due.addingTimeInterval(75))
        #expect(resumption.textDate == due.addingTimeInterval(60))
        #expect(resumption.nextDue == due.addingTimeInterval(90))

        let exactly = DateRefreshSchedule.resume(due: due, now: due)
        #expect(exactly.textDate == due)
        #expect(exactly.nextDue == due.addingTimeInterval(30))
    }

    @Test func aLongClosedPanelCatchesUpInOneStep() {
        let resumption = DateRefreshSchedule.resume(due: due, now: due.addingTimeInterval(86_400 + 7))
        #expect(resumption.textDate == due.addingTimeInterval(86_400))
        #expect(resumption.nextDue == due.addingTimeInterval(86_430))
    }
}
