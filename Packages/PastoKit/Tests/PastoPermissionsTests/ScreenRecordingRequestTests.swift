import Foundation
@testable import PastoPermissions
import Testing

/// When Pasto opens itself again after System Settings quits it, and where it takes the user.
struct ScreenRecordingRequestTests {
    private let asked = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private var request: ScreenRecordingRequest { ScreenRecordingRequest(origin: .onboarding, date: asked) }
    private var systemSettingsQuit: QuitRequest { .appleEvent(sender: .systemSettings, hasReason: false) }

    // MARK: Pending

    @Test func pendingForAQuarterOfAnHour() {
        #expect(request.isPending(at: asked))
        #expect(request.isPending(at: asked.addingTimeInterval(14 * 60)))
        #expect(!request.isPending(at: asked.addingTimeInterval(15 * 60)))
    }

    @Test func aClockSetBackALittleStillCounts() {
        #expect(request.isPending(at: asked.addingTimeInterval(-30)))
        #expect(!request.isPending(at: asked.addingTimeInterval(-3600)))
    }

    // MARK: Relaunching

    @Test func systemSettingsQuittingWhileARequestIsPendingRelaunches() {
        #expect(request.callsForRelaunch(after: systemSettingsQuit, at: asked.addingTimeInterval(60)))
    }

    @Test func aSenderThatCannotBeToldCountsAsSystemSettings() {
        #expect(request.callsForRelaunch(after: .appleEvent(sender: .unknown, hasReason: false), at: asked))
    }

    @Test func quittingFromPastoItselfNeverRelaunches() {
        #expect(!request.callsForRelaunch(after: .direct, at: asked))
    }

    @Test(arguments: ["com.apple.dock", "org.sparkle-project.Sparkle.Updater", "/usr/bin/osascript"])
    func anotherAppQuittingPastoDoesNotRelaunch(_ sender: String) {
        #expect(!request.callsForRelaunch(after: .appleEvent(sender: .other(sender), hasReason: false), at: asked))
    }

    @Test func loggingOutOrShuttingDownDoesNotRelaunch() {
        #expect(!request.callsForRelaunch(after: .appleEvent(sender: .systemSettings, hasReason: true), at: asked))
        #expect(!request.callsForRelaunch(after: .appleEvent(sender: .unknown, hasReason: true), at: asked))
    }

    @Test func anOldRequestDoesNotRelaunch() {
        #expect(!request.callsForRelaunch(after: systemSettingsQuit, at: asked.addingTimeInterval(3600)))
    }

    // MARK: Launching afterwards

    @Test func grantedSinceItWasAskedForResumesAndForgetsTheRequest() {
        #expect(request.resumption(at: asked.addingTimeInterval(60), isGranted: true) == .resume(.onboarding, keepsRequest: false))
    }

    @Test func reopenedForItButStillNotGrantedResumesAndKeepsTheRequest() {
        var request = ScreenRecordingRequest(origin: .panel, date: asked)
        request.relaunchDate = asked.addingTimeInterval(30)

        #expect(request.resumption(at: asked.addingTimeInterval(35), isGranted: false) == .resume(.panel, keepsRequest: true))
    }

    @Test func anOrdinaryLaunchWhileTheUserIsDecidingKeepsTheRequest() {
        #expect(request.resumption(at: asked.addingTimeInterval(60), isGranted: false) == .keep)
    }

    @Test func anOldRequestIsDiscarded() {
        #expect(request.resumption(at: asked.addingTimeInterval(3600), isGranted: true) == .discard)
        #expect(request.resumption(at: asked.addingTimeInterval(3600), isGranted: false) == .discard)
    }

    @Test func survivesBeingSavedAndRead() throws {
        var request = ScreenRecordingRequest(origin: .settings, date: asked)
        request.relaunchDate = asked.addingTimeInterval(10)

        let data = try JSONEncoder().encode(request)

        #expect(try JSONDecoder().decode(ScreenRecordingRequest.self, from: data) == request)
    }
}
