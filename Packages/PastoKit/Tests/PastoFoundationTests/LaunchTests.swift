import Foundation
import PastoFoundation
import Testing

struct LaunchRecordTests {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)

    private func record() -> LaunchRecord {
        LaunchRecord(processIdentifier: 42, version: "1.0.3 (4)", startedAt: start, wasLaunchedAsLoginItem: false, location: "applications")
    }

    @Test func phasesAreRecordedWithTheirTimes() {
        var record = record()
        record.enter(.checkingOtherCopies, at: start.addingTimeInterval(0.1))
        record.enter(.openingStore, at: start.addingTimeInterval(0.4))
        record.enter(.openingStore, at: start.addingTimeInterval(0.9))

        #expect(record.steps.map(\.phase) == [.started, .checkingOtherCopies, .openingStore])
        #expect(record.phase == .openingStore)
        #expect(record.phaseStartedAt == start.addingTimeInterval(0.4))
        #expect(record.secondsInPhase(at: start.addingTimeInterval(1.4)) == 1)
    }

    @Test func nothingIsRecordedOnceReady() {
        var record = record()
        record.enter(.ready, at: start.addingTimeInterval(1))
        record.enter(.connecting, at: start.addingTimeInterval(2))

        #expect(record.phase == .ready)
        #expect(record.isReady)
    }

    @Test func aPhaseThatWaitsForTheAppStallsPastItsLimit() throws {
        var record = record()
        record.enter(.openingStore, at: start)
        let limit = try #require(LaunchPhase.openingStore.stallLimit)

        #expect(!record.isStalled(at: start.addingTimeInterval(limit - 1)))
        #expect(record.isStalled(at: start.addingTimeInterval(limit + 1)))
    }

    @Test func waitingForTheUserNeverStalls() {
        for phase in [LaunchPhase.relocating, .storeFailure, .welcome] {
            var record = record()
            record.enter(phase, at: start)

            #expect(phase.isWaitingForUser)
            #expect(phase.stallLimit == nil)
            #expect(!record.isStalled(at: start.addingTimeInterval(3600)))
        }
    }

    @Test func aReadyOrQuitLaunchIsNotStalled() {
        var ready = record()
        ready.enter(.ready, at: start)
        var quit = record()
        quit.enter(.startingApp, at: start)
        quit.markQuit()

        #expect(!ready.isStalled(at: start.addingTimeInterval(3600)))
        #expect(!quit.isStalled(at: start.addingTimeInterval(3600)))
    }

    @Test func everyPhaseThatWaitsForTheAppHasALimit() {
        for phase in LaunchPhase.allCases where !phase.isWaitingForUser && phase != .ready {
            #expect(phase.stallLimit != nil, "\(phase)")
        }
    }

    @Test func endings() {
        var ready = record()
        ready.enter(.ready, at: start)
        var quitDuringWelcome = record()
        quitDuringWelcome.enter(.welcome, at: start)
        quitDuringWelcome.markQuit()
        var interrupted = record()
        interrupted.enter(.openingStore, at: start)

        #expect(ready.ending == .ready)
        #expect(quitDuringWelcome.ending == .quit(during: .welcome))
        #expect(interrupted.ending == .interrupted(during: .openingStore))
    }

    @Test func theRecordStoreKeepsTheRecord() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "PastoLaunch-\(UUID().uuidString)", directoryHint: .isDirectory)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LaunchRecordStore(directory: directory)
        var record = record()
        record.enter(.welcome, at: start.addingTimeInterval(0.5))

        #expect(store.load() == nil)
        try store.save(record)

        #expect(store.load() == record)
    }

    @Test func aReportNamesThePhaseAndCarriesNoPaths() throws {
        var record = record()
        record.enter(.openingStore, at: start)
        let report = LaunchReport(kind: .stalled, record: record, secondsInPhase: 61.234, mainThreadSilence: 60.98, system: "macOS")

        let json = try #require(String(data: try report.encoded(), encoding: .utf8))

        #expect(json.contains("\"kind\" : \"stalled\""))
        #expect(json.contains("\"phase\" : \"openingStore\""))
        #expect(json.contains("61.2"))
        #expect(!json.contains("/Users/"))
    }
}

struct SingleInstancePolicyTests {
    private typealias Copy = SingleInstancePolicy.Copy
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func copy(_ pid: Int32, startedSecondsAgo seconds: TimeInterval?, version: String? = "1.0.2", stuck: Bool = false) -> Copy {
        Copy(processIdentifier: pid, launchDate: seconds.map { now.addingTimeInterval(-$0) }, version: version, isStuckLaunching: stuck)
    }

    @Test func aCopyAloneGoesOn() {
        let me = copy(10, startedSecondsAgo: 0)

        #expect(SingleInstancePolicy.olderCopies(than: me, among: []).isEmpty)
        #expect(SingleInstancePolicy.decision(for: me, olderCopiesStillRunning: [], needsRelocation: false) == .proceed)
    }

    @Test func theYoungerCopyGivesWayToTheOlder() {
        let me = copy(20, startedSecondsAgo: 0)
        let older = copy(10, startedSecondsAgo: 60)

        #expect(SingleInstancePolicy.olderCopies(than: me, among: [older]) == [older])
        #expect(SingleInstancePolicy.decision(for: me, olderCopiesStillRunning: [older], needsRelocation: false) == .handOver(to: 10))
    }

    /// Two copies started at once settle on one: the older goes on without waiting.
    @Test func theOlderCopyIgnoresAYoungerOne() {
        let me = copy(10, startedSecondsAgo: 0.2)
        let younger = copy(20, startedSecondsAgo: 0.1)

        #expect(SingleInstancePolicy.olderCopies(than: me, among: [younger]).isEmpty)
        #expect(SingleInstancePolicy.decision(for: me, olderCopiesStillRunning: [younger], needsRelocation: false) == .proceed)
    }

    @Test func equalLaunchDatesGoByProcessIdentifier() {
        let low = copy(10, startedSecondsAgo: 1)
        let high = copy(20, startedSecondsAgo: 1)

        #expect(SingleInstancePolicy.isOlder(low, than: high))
        #expect(!SingleInstancePolicy.isOlder(high, than: low))
    }

    @Test func aCopyWithoutALaunchDateCountsAsOlder() {
        let me = copy(10, startedSecondsAgo: 0)
        let unknown = copy(20, startedSecondsAgo: nil)

        #expect(SingleInstancePolicy.isOlder(unknown, than: me))
        #expect(!SingleInstancePolicy.isOlder(me, than: unknown))
    }

    /// A copy that moved itself into Applications opens the new one and quits: once it is gone
    /// the new copy goes on.
    @Test func anOlderCopyThatQuitLeavesTheWayFree() {
        let me = copy(20, startedSecondsAgo: 0)

        #expect(SingleInstancePolicy.decision(for: me, olderCopiesStillRunning: [], needsRelocation: false) == .proceed)
    }

    @Test func aCopyStuckLaunchingIsReplaced() {
        let me = copy(20, startedSecondsAgo: 0)
        let stuck = copy(10, startedSecondsAgo: 120, stuck: true)

        #expect(SingleInstancePolicy.decision(for: me, olderCopiesStillRunning: [stuck], needsRelocation: false) == .replaceStuckCopy(10))
    }

    /// A newer version opened from the disk image goes on to offer moving itself, which replaces
    /// the copy that is running; the same or an older version gives way.
    @Test func aNewerVersionToBeMovedGoesOnToReplaceTheRunningCopy() {
        let running = copy(10, startedSecondsAgo: 3600, version: "1.0.2")
        let newer = copy(20, startedSecondsAgo: 0, version: "1.0.10")
        let same = copy(30, startedSecondsAgo: 0, version: "1.0.2")

        #expect(SingleInstancePolicy.decision(for: newer, olderCopiesStillRunning: [running], needsRelocation: true) == .proceedToReplace(10))
        #expect(SingleInstancePolicy.decision(for: newer, olderCopiesStillRunning: [running], needsRelocation: false) == .handOver(to: 10))
        #expect(SingleInstancePolicy.decision(for: same, olderCopiesStillRunning: [running], needsRelocation: true) == .handOver(to: 10))
    }

    @Test func theOldestOfSeveralIsTheOneThatCounts() {
        let me = copy(30, startedSecondsAgo: 0)
        let old = copy(10, startedSecondsAgo: 100)
        let older = copy(20, startedSecondsAgo: 200)

        #expect(SingleInstancePolicy.decision(for: me, olderCopiesStillRunning: [old, older], needsRelocation: false) == .handOver(to: 20))
    }

    @Test func versionsCompareByTheirNumbers() {
        #expect(SingleInstancePolicy.isNewer("1.0.10", than: "1.0.9"))
        #expect(SingleInstancePolicy.isNewer("1.1", than: "1.0.9"))
        #expect(!SingleInstancePolicy.isNewer("1.0.2", than: "1.0.2"))
        #expect(!SingleInstancePolicy.isNewer(nil, than: "1.0"))
        #expect(!SingleInstancePolicy.isNewer("1.0", than: nil))
    }
}

struct DeadlineTests {
    @Test func returnsTheResultInTime() async throws {
        let value = try await Deadline.run(within: .seconds(5)) { 7 }

        #expect(value == 7)
    }

    @Test func givesUpWhenTheTimeIsUp() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        let value = try await Deadline.run(within: .milliseconds(50)) { () async throws -> Int in
            try await Task.sleep(for: .seconds(10))
            return 7
        }

        #expect(value == nil)
        #expect(clock.now - start < .seconds(5))
    }

    /// An operation that never answers — a continuation nobody resumes in time — does not hold
    /// the caller.
    @Test func givesUpOnAnOperationThatIgnoresCancellation() async {
        let clock = ContinuousClock()
        let start = clock.now
        let finished = await Deadline.finishes(within: .milliseconds(50)) {
            await withCheckedContinuation { continuation in
                DispatchQueue.global().asyncAfter(deadline: .now() + 2) { continuation.resume() }
            }
        }

        #expect(!finished)
        #expect(clock.now - start < .seconds(1.5))
    }

    @Test func throwsTheOperationsError() async {
        struct Failure: Error {}

        await #expect(throws: Failure.self) {
            _ = try await Deadline.run(within: .seconds(5)) { () async throws -> Int in throw Failure() }
        }
    }
}
