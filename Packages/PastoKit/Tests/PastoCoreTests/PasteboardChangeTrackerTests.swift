import Foundation
@testable import PastoCore
import Testing

struct PasteboardChangeTrackerTests {
    private typealias Read = PasteboardChangeTracker.Read

    /// A tracker that started monitoring a pasteboard whose change count was 10.
    private func monitoringTracker() -> PasteboardChangeTracker {
        var tracker = PasteboardChangeTracker(changeToken: 3, droppedSyncWindow: 1)
        tracker.startMonitoring(changeCount: 10)
        return tracker
    }

    private func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSinceReferenceDate: seconds)
    }

    @Test func whatIsOnThePasteboardWhenMonitoringStartsCountsAsSeen() {
        var tracker = monitoringTracker()

        #expect(tracker.changeToken == 10)
        #expect(tracker.poll(changeCount: 10) == .unchanged)
    }

    @Test func aChangeIsDetectedOnce() {
        var tracker = monitoringTracker()

        #expect(tracker.poll(changeCount: 11) == .changed)
        #expect(tracker.poll(changeCount: 11) == .unchanged)
        #expect(tracker.poll(changeCount: 13) == .changed)
    }

    @Test func aReadTakesTheLiveChangeCountAndCountsFromTheLastRead() {
        var tracker = monitoringTracker()
        _ = tracker.poll(changeCount: 11)

        // Two more changes arrived while waiting for the pasteboard to settle.
        let first = tracker.beginRead(changeCount: 13, at: date(0))
        #expect(first == Read(token: 13, coveredChanges: 3))
        #expect(tracker.changeToken == 13)
        #expect(tracker.poll(changeCount: 13) == .unchanged)

        let second = tracker.beginRead(changeCount: 14, at: date(5))
        #expect(second == Read(token: 14, coveredChanges: 1))
    }

    @Test func aVetoedReadIsCountedByTheNextOneWithinTheWindow() {
        var tracker = monitoringTracker()
        let vetoed = tracker.beginRead(changeCount: 12, at: date(0))
        tracker.cancelRead(vetoed, at: date(0))

        let next = tracker.beginRead(changeCount: 13, at: date(1))

        #expect(next == Read(token: 13, coveredChanges: 3))
    }

    @Test func aVetoedReadIsForgottenAfterTheWindow() {
        var tracker = monitoringTracker()
        let vetoed = tracker.beginRead(changeCount: 12, at: date(0))
        tracker.cancelRead(vetoed, at: date(0))

        let next = tracker.beginRead(changeCount: 13, at: date(1.5))

        #expect(next == Read(token: 13, coveredChanges: 1))
    }

    @Test func theVetoedBaselineIsUsedUpByTheReadThatFollows() {
        var tracker = monitoringTracker()
        let vetoed = tracker.beginRead(changeCount: 12, at: date(0))
        tracker.cancelRead(vetoed, at: date(0))
        _ = tracker.beginRead(changeCount: 13, at: date(0.1))

        let third = tracker.beginRead(changeCount: 14, at: date(0.2))

        #expect(third == Read(token: 14, coveredChanges: 1))
    }

    @Test func consecutiveVetoesKeepCountingFromTheLastDeliveredRead() {
        var tracker = monitoringTracker()
        let first = tracker.beginRead(changeCount: 11, at: date(0))
        tracker.cancelRead(first, at: date(0))
        let second = tracker.beginRead(changeCount: 12, at: date(0.5))
        tracker.cancelRead(second, at: date(0.5))

        let third = tracker.beginRead(changeCount: 13, at: date(1))

        #expect(third == Read(token: 13, coveredChanges: 3))
    }

    @Test func aVetoLeavesNoBaselineIfPastoWroteMeanwhile() {
        var tracker = monitoringTracker()
        let vetoed = tracker.beginRead(changeCount: 12, at: date(0))
        tracker.didWrite(changeCount: 13)
        tracker.cancelRead(vetoed, at: date(0))

        let next = tracker.beginRead(changeCount: 14, at: date(0.1))

        #expect(next == Read(token: 14, coveredChanges: 1))
    }

    @Test func restartingMonitoringForgetsAVetoedRead() {
        var tracker = monitoringTracker()
        let vetoed = tracker.beginRead(changeCount: 12, at: date(0))
        tracker.cancelRead(vetoed, at: date(0))

        tracker.startMonitoring(changeCount: 20)

        #expect(tracker.poll(changeCount: 20) == .unchanged)
        #expect(tracker.beginRead(changeCount: 21, at: date(0.1)) == Read(token: 21, coveredChanges: 1))
    }

    @Test func anEmptyPasteboardIsLookedAtAgainUntilItFills() {
        var tracker = monitoringTracker()
        let read = tracker.beginRead(changeCount: 11, at: date(0))
        tracker.acceptRead(read, isEmpty: true)

        #expect(tracker.poll(changeCount: 11) == .mayHaveBeenFilled)
        #expect(tracker.poll(changeCount: 11) == .mayHaveBeenFilled)

        tracker.contentAppeared()
        #expect(tracker.poll(changeCount: 11) == .unchanged)
    }

    @Test func onlyAnEmptyReadIsLookedAtAgain() {
        var tracker = monitoringTracker()
        let empty = tracker.beginRead(changeCount: 11, at: date(0))
        tracker.acceptRead(empty, isEmpty: true)

        // A later read with content replaces the memory of the empty one…
        let full = tracker.beginRead(changeCount: 12, at: date(1))
        tracker.acceptRead(full, isEmpty: false)
        #expect(tracker.poll(changeCount: 12) == .unchanged)

        // …and so does a veto.
        let emptyAgain = tracker.beginRead(changeCount: 13, at: date(2))
        tracker.acceptRead(emptyAgain, isEmpty: true)
        let vetoed = tracker.beginRead(changeCount: 13, at: date(3))
        tracker.cancelRead(vetoed, at: date(3))
        #expect(tracker.poll(changeCount: 13) == .unchanged)
    }

    @Test func pollsDoNotSeePastosOwnWrites() {
        var tracker = monitoringTracker()

        tracker.didWrite(changeCount: 11)

        #expect(tracker.changeToken == 11)
        #expect(tracker.poll(changeCount: 11) == .unchanged)
    }

    @Test func aReadIsDroppedIfPastoWroteAtOrAfterIt() {
        var tracker = monitoringTracker()
        #expect(!tracker.isReplacedByOwnWrite(Read(token: 10, coveredChanges: 0)))

        tracker.didWrite(changeCount: 12)

        // Read before the write, read of the write itself, read of a later copy.
        #expect(tracker.isReplacedByOwnWrite(Read(token: 11, coveredChanges: 1)))
        #expect(tracker.isReplacedByOwnWrite(Read(token: 12, coveredChanges: 1)))
        #expect(!tracker.isReplacedByOwnWrite(Read(token: 13, coveredChanges: 1)))
    }
}
