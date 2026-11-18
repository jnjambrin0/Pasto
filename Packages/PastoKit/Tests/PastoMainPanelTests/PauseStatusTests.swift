import Foundation
import Testing
@testable import PastoMainPanel

/// The pause indicator in the panel's toolbar.
@Suite struct PauseStatusTests {
    private let utc = TimeZone(identifier: "UTC") ?? .gmt

    @Test func saysNothingWhileCaptureRuns() {
        #expect(PauseStatus.running.indicatorText() == nil)
    }

    @Test func anOpenEndedPauseHasNoTime() {
        #expect(PauseStatus.paused(until: nil).indicatorText() == PanelStrings.paused)
    }

    /// 2001-01-01 18:05 UTC: the hour is not turned into "6 PM".
    @Test func aTimedPauseSaysUntilWhenOnA24HourClock() {
        let date = Date(timeIntervalSinceReferenceDate: 18 * 3_600 + 5 * 60)
        #expect(PauseStatus.paused(until: date).indicatorText(timeZone: utc) == PanelStrings.pausedUntil("18:05"))
    }

    @Test func theTimeIsTheOneInTheGivenTimeZone() throws {
        let date = Date(timeIntervalSinceReferenceDate: 23 * 3_600 + 30 * 60)
        let madrid = try #require(TimeZone(identifier: "Europe/Madrid"))
        #expect(PauseStatus.paused(until: date).indicatorText(timeZone: madrid) == PanelStrings.pausedUntil("00:30"))
    }
}
