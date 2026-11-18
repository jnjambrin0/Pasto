import Foundation
@testable import PastoOnboarding
import Testing

/// Where Pasto runs from, and how it gets into an Applications folder.
struct ApplicationLocationTests {
    private let home = URL(filePath: "/Users/someone", directoryHint: .isDirectory)

    private func location(_ path: String, isOnReadOnlyVolume: Bool = false) -> ApplicationLocation {
        ApplicationLocation(bundleURL: URL(filePath: path, directoryHint: .isDirectory), isOnReadOnlyVolume: isOnReadOnlyVolume, homeDirectory: home)
    }

    // MARK: Location

    @Test(arguments: [
        "/Applications/Pasto.app",
        "/Applications/Utilities/Pasto.app",
        "/Users/someone/Applications/Pasto.app",
        "/Users/someone/Applications/Tools/Pasto.app",
    ])
    func anApplicationsFolderIsFine(path: String) {
        #expect(location(path).problem == nil)
    }

    @Test(arguments: [
        "/Users/someone/Downloads/Pasto.app",
        "/Users/someone/Desktop/Pasto.app",
        "/ApplicationsOld/Pasto.app",
        "/Users/other/Applications/Pasto.app",
        "/Applications",
    ])
    func anywhereElseIsOutsideApplications(path: String) {
        #expect(location(path).problem == .outsideApplications)
        #expect(!location(path).isEphemeral)
    }

    @Test func aDiskImageIsAReadOnlyVolume() {
        let dmg = location("/Volumes/Pasto/Pasto.app", isOnReadOnlyVolume: true)

        #expect(dmg.problem == .readOnlyVolume)
        #expect(dmg.isEphemeral)
    }

    @Test func aTranslocatedCopyIsTranslocatedWhateverElseHolds() {
        let translocated = location("/private/var/folders/xy/abc/T/AppTranslocation/1A2B-3C4D/d/Pasto.app", isOnReadOnlyVolume: true)

        #expect(translocated.problem == .translocated)
        #expect(translocated.isEphemeral)
    }

    // MARK: Relocation

    @Test func nothingToMoveFromAnApplicationsFolder() {
        #expect(ApplicationRelocation.plan(
            for: location("/Applications/Pasto.app"),
            translocatedOriginal: nil,
            isSystemApplicationsFolderWritable: true,
            homeDirectory: home
        ) == nil)
    }

    @Test func fromDownloadsTheCopyGoesToApplicationsAndTheDownloadToTheTrash() throws {
        let plan = try #require(ApplicationRelocation.plan(
            for: location("/Users/someone/Downloads/Pasto.app"),
            translocatedOriginal: nil,
            isSystemApplicationsFolderWritable: true,
            homeDirectory: home
        ))

        #expect(plan.source.path == "/Users/someone/Downloads/Pasto.app")
        #expect(plan.destination.path == "/Applications/Pasto.app")
        #expect(plan.originalToTrash?.path == "/Users/someone/Downloads/Pasto.app")
        #expect(plan.copiesBundle)
    }

    @Test func withoutWriteAccessToApplicationsTheUsersOwnFolderIsUsed() throws {
        let plan = try #require(ApplicationRelocation.plan(
            for: location("/Users/someone/Downloads/Pasto.app"),
            translocatedOriginal: nil,
            isSystemApplicationsFolderWritable: false,
            homeDirectory: home
        ))

        #expect(plan.destination.path == "/Users/someone/Applications/Pasto.app")
    }

    @Test func fromADiskImageNothingGoesToTheTrash() throws {
        let plan = try #require(ApplicationRelocation.plan(
            for: location("/Volumes/Pasto/Pasto.app", isOnReadOnlyVolume: true),
            translocatedOriginal: nil,
            isSystemApplicationsFolderWritable: true,
            homeDirectory: home
        ))

        #expect(plan.destination.path == "/Applications/Pasto.app")
        #expect(plan.originalToTrash == nil)
    }

    @Test func aTranslocatedCopyIsCopiedFromItsMirrorAndItsOriginalGoesToTheTrash() throws {
        let mirror = "/private/var/folders/xy/abc/T/AppTranslocation/1A2B/d/Pasto.app"
        let original = URL(filePath: "/Users/someone/Downloads/Pasto.app", directoryHint: .isDirectory)
        let plan = try #require(ApplicationRelocation.plan(
            for: location(mirror, isOnReadOnlyVolume: true),
            translocatedOriginal: (original, false),
            isSystemApplicationsFolderWritable: true,
            homeDirectory: home
        ))

        #expect(plan.source.path == mirror)
        #expect(plan.destination.path == "/Applications/Pasto.app")
        #expect(plan.originalToTrash == original)
        #expect(plan.copiesBundle)
    }

    @Test func aTranslocatedCopyFromADiskImageLeavesTheImageAlone() throws {
        let plan = try #require(ApplicationRelocation.plan(
            for: location("/private/var/folders/xy/abc/T/AppTranslocation/1A2B/d/Pasto.app", isOnReadOnlyVolume: true),
            translocatedOriginal: (URL(filePath: "/Volumes/Pasto/Pasto.app", directoryHint: .isDirectory), true),
            isSystemApplicationsFolderWritable: true,
            homeDirectory: home
        ))

        #expect(plan.originalToTrash == nil)
    }

    @Test func aTranslocatedCopyWhoseOriginalIsUnknownCannotBeMoved() {
        #expect(ApplicationRelocation.plan(
            for: location("/private/var/folders/xy/abc/T/AppTranslocation/1A2B/d/Pasto.app", isOnReadOnlyVolume: true),
            translocatedOriginal: nil,
            isSystemApplicationsFolderWritable: true,
            homeDirectory: home
        ) == nil)
    }

    @Test func aTranslocatedCopyAlreadyInApplicationsOnlyLosesItsQuarantine() throws {
        let original = URL(filePath: "/Applications/Pasto.app", directoryHint: .isDirectory)
        let plan = try #require(ApplicationRelocation.plan(
            for: location("/private/var/folders/xy/abc/T/AppTranslocation/1A2B/d/Pasto.app", isOnReadOnlyVolume: true),
            translocatedOriginal: (original, false),
            isSystemApplicationsFolderWritable: true,
            homeDirectory: home
        ))

        #expect(!plan.copiesBundle)
        #expect(plan.destination == original)
        #expect(plan.originalToTrash == nil)
    }
}
