import AppKit
@testable import PastoUI
import Testing

/// The state behind a "Keep History" slider: what the knob shows, the capacity in effect, and a
/// lower limit waiting to be confirmed because it deletes items.
struct HistoryCapacityModelTests {
    /// A store of 30 days in which only limits under a week would delete something.
    private final class FakeStore {
        var days = 30
        var expiredItemCount: (Int) -> Int = { $0 != 0 && $0 < 7 ? 3 : 0 }
        var writes: [Int] = []
        let (written, didWrite) = AsyncStream.makeStream(of: Void.self)

        var storage: HistoryCapacityModel.Storage {
            HistoryCapacityModel.Storage(
                days: { self.days },
                expiredItemCount: { self.expiredItemCount($0) },
                setDays: { days in
                    self.days = days
                    self.writes.append(days)
                    self.didWrite.yield()
                }
            )
        }

        func nextWrite() async {
            var iterator = written.makeAsyncIterator()
            await iterator.next()
        }
    }

    /// Stands in for the clock: remembers every wait and returns at once.
    private actor WaitLog {
        private(set) var durations: [Duration] = []

        func record(_ duration: Duration) {
            durations.append(duration)
        }
    }

    private let store = FakeStore()

    private func makeModel() -> HistoryCapacityModel {
        HistoryCapacityModel(storage: store.storage)
    }

    @Test func draggingOnlyPreviews() {
        let model = makeModel()

        _ = model.sliderMoved(to: 4, isInteractive: true, isFinal: false)

        #expect(model.shownDays == 365)
        #expect(model.isTracking)
        #expect(model.savedDays == 30)
        #expect(store.writes.isEmpty)
    }

    @Test func lettingGoStoresALimitThatDeletesNothing() async {
        let model = makeModel()

        let position = model.sliderMoved(to: 4, isInteractive: true, isFinal: true)
        await store.nextWrite()

        #expect(position == 4)
        #expect(!model.isTracking)
        #expect(model.savedDays == 365)
        #expect(model.pendingDays == nil)
        #expect(store.writes == [365])
    }

    @Test func aLimitThatDeletesItemsWaitsToBeConfirmed() async {
        let model = makeModel()

        _ = model.sliderMoved(to: 1, isInteractive: true, isFinal: true)

        #expect(model.pendingDays == 1)
        #expect(model.savedDays == 30)
        #expect(store.writes.isEmpty)

        model.confirmPendingCapacity()
        await store.nextWrite()

        #expect(model.pendingDays == nil)
        #expect(model.savedDays == 1)
        #expect(store.writes == [1])
    }

    @Test func discardingPutsTheKnobBack() {
        let model = makeModel()

        _ = model.sliderMoved(to: 1, isInteractive: true, isFinal: true)
        model.discardPendingCapacity()

        #expect(model.pendingDays == nil)
        #expect(model.shownDays == 30)
        #expect(model.sliderPosition == 3)
        #expect(store.writes.isEmpty)
    }

    @Test func discardingAfterConfirmingChangesNothing() async {
        let model = makeModel()

        _ = model.sliderMoved(to: 1, isInteractive: true, isFinal: true)
        model.confirmPendingCapacity()
        model.discardPendingCapacity()
        await store.nextWrite()

        #expect(model.shownDays == 1)
        #expect(model.savedDays == 1)
    }

    @Test func lettingGoWhereItWasStillAsksBeforeDeleting() {
        // Items older than the limit in effect, which retention has not removed yet.
        store.expiredItemCount = { _ in 2 }
        let model = makeModel()

        _ = model.sliderMoved(to: 3, isInteractive: true, isFinal: true)

        #expect(model.pendingDays == 30)
    }

    @Test func theCapacityInEffectIsNotWrittenAgain() {
        let model = makeModel()
        var reportedWrites = 0
        model.onWrite = { reportedWrites += 1 }

        _ = model.sliderMoved(to: 3, isInteractive: false, isFinal: true)

        #expect(model.pendingDays == nil)
        #expect(model.shownDays == 30)
        #expect(store.writes.isEmpty)
        #expect(reportedWrites == 0)
    }

    // MARK: Steps from the keyboard

    /// A wait that only ends when it is cancelled.
    private static let endlessSleep: @Sendable (Duration) async throws -> Void = { _ in
        try await Task.sleep(for: .seconds(3600))
    }

    @Test func aStepIsShownButNotAppliedAtOnce() {
        let model = HistoryCapacityModel(storage: store.storage, sleep: Self.endlessSleep)

        #expect(model.sliderStepped(to: 4) == 4)

        #expect(model.shownDays == 365)
        #expect(!model.isTracking)
        #expect(model.savedDays == 30)
        #expect(model.pendingDays == nil)
        #expect(store.writes.isEmpty)
    }

    @Test func aStepIsAppliedOnceTheKnobStaysPut() async {
        let waits = WaitLog()
        let model = HistoryCapacityModel(storage: store.storage, sleep: { await waits.record($0) })

        _ = model.sliderStepped(to: 4)
        await model.steppedChange?.value
        await store.nextWrite()

        #expect(await waits.durations == [.milliseconds(800)])
        #expect(model.savedDays == 365)
        #expect(store.writes == [365])
    }

    @Test func onlyTheLastOfSeveralStepsIsApplied() async {
        let model = HistoryCapacityModel(storage: store.storage, sleep: Self.endlessSleep)

        _ = model.sliderStepped(to: 4)
        _ = model.sliderStepped(to: 5)
        model.settleSteppedChange()
        await store.nextWrite()

        #expect(model.savedDays == 0)
        #expect(store.writes == [0])
    }

    @Test func aStepThatDeletesItemsAsksOnlyOnceSettled() {
        let model = HistoryCapacityModel(storage: store.storage, sleep: Self.endlessSleep)

        _ = model.sliderStepped(to: 1)
        #expect(model.pendingDays == nil)

        model.settleSteppedChange()
        #expect(model.pendingDays == 1)
        #expect(store.writes.isEmpty)
    }

    @Test func settlingWithoutAStepDoesNothing() {
        store.expiredItemCount = { _ in 2 }
        let model = HistoryCapacityModel(storage: store.storage, sleep: Self.endlessSleep)

        model.settleSteppedChange()

        #expect(model.pendingDays == nil)
        #expect(store.writes.isEmpty)
    }

    @Test func theMouseTakesOverFromAStep() {
        let model = HistoryCapacityModel(storage: store.storage, sleep: Self.endlessSleep)

        _ = model.sliderStepped(to: 1)
        _ = model.sliderMoved(to: 4, isInteractive: true, isFinal: false)
        model.settleSteppedChange()

        // Only the mouse's release settles now.
        #expect(model.pendingDays == nil)
        #expect(model.isTracking)
        #expect(store.writes.isEmpty)
    }

    @Test func slidersTellTheMouseFromTheKeyboard() {
        #expect(HistoryCapacitySliderInput(eventType: .leftMouseDown, wasDragging: false) == .tracking)
        #expect(HistoryCapacitySliderInput(eventType: .leftMouseDragged, wasDragging: true) == .tracking)
        #expect(HistoryCapacitySliderInput(eventType: .leftMouseUp, wasDragging: true) == .released(isInteractive: true))
        #expect(HistoryCapacitySliderInput(eventType: .leftMouseUp, wasDragging: false) == .released(isInteractive: false))
        #expect(HistoryCapacitySliderInput(eventType: .keyDown, wasDragging: false) == .stepped)
        #expect(HistoryCapacitySliderInput(eventType: nil, wasDragging: false) == .stepped)
    }

    @Test func withoutTheMouseAStepOffAYearGoesByWhatWasShownLast() {
        store.days = 30
        let model = makeModel()
        _ = model.sliderMoved(to: 4, isInteractive: true, isFinal: false)

        // The capacity in effect is a month, but the slider shows a year: the step goes on to forever.
        #expect(model.sliderMoved(to: 4.1, isInteractive: false, isFinal: false) == 5)
        #expect(model.shownDays == 0)
    }
}
