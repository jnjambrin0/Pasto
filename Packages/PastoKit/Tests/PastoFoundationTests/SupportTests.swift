import Foundation
@testable import PastoFoundation
import Testing

struct AppIdentityTests {
    @Test func anAppGoesByTheIdentifierItDeclares() {
        let url = URL(filePath: "/Applications/Pasto.app", directoryHint: .isDirectory)

        #expect(AppIdentity.bundleIdentifier(declared: "jnjambrino.Pasto", bundleURL: url) == "jnjambrino.Pasto")
        #expect(AppIdentity.bundleIdentifier(declared: "jnjambrino.Pasto.dev", bundleURL: url) == "jnjambrino.Pasto.dev")
    }

    /// Tests and tools run from other bundles, or none: they use the published identifier.
    @Test func outsideAnAppItIsThePublishedIdentifier() {
        let tool = URL(filePath: "/Applications/Xcode.app/Contents/Developer/usr/bin", directoryHint: .isDirectory)
        let app = URL(filePath: "/Applications/Pasto.app", directoryHint: .isDirectory)

        #expect(AppIdentity.bundleIdentifier(declared: "com.apple.dt.xctest.tool", bundleURL: tool) == "jnjambrino.Pasto")
        #expect(AppIdentity.bundleIdentifier(declared: nil, bundleURL: app) == "jnjambrino.Pasto")
        #expect(AppIdentity.bundleIdentifier(declared: "", bundleURL: app) == "jnjambrino.Pasto")
    }

    @Test func theLogSubsystemAndTheDataFolderFollowIt() {
        #expect(Log.subsystem == AppIdentity.bundleIdentifier)
        #expect(AppIdentity.applicationSupportDirectory.lastPathComponent == AppIdentity.bundleIdentifier)
    }
}

struct SupportLinksTests {
    private let details = SystemDetails(appVersion: "1.0.0 (311)", systemVersion: "27.2 (26C123)", macModel: "Mac15,3")

    @Test func theContactPageCarriesTheVersions() throws {
        let url = SupportLinks.contactPage(details: details)
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.scheme == "https")
        #expect(components.host == "pasto.jnjambrino.com")
        #expect(components.path == "/contact")
        #expect(components.queryItems == [
            URLQueryItem(name: "app", value: "1.0.0 (311)"),
            URLQueryItem(name: "macos", value: "27.2 (26C123)"),
            URLQueryItem(name: "mac", value: "Mac15,3"),
        ])
    }

    @Test func theEmailHasTheSubjectThePromptAndTheVersions() throws {
        let url = SupportLinks.email(subject: "Pasto: a problem", prompt: "What happened?", details: details)
        let string = url.absoluteString

        #expect(string.hasPrefix("mailto:hello@jnjambrino.com?subject=Pasto%3A%20a%20problem&body="))
        let body = try #require(string.components(separatedBy: "&body=").last?.removingPercentEncoding)
        #expect(body == "What happened?\n\n\n—\nPasto 1.0.0 (311)\nmacOS 27.2 (26C123)\nMac15,3\n")
    }

    /// What would end a header or start another must reach the mail app as text.
    @Test func headerValuesEscapeEverythingButUnreservedCharacters() {
        #expect(SupportLinks.mailtoEncoded("a&b=c+d#e?f") == "a%26b%3Dc%2Bd%23e%3Ff")
        #expect(SupportLinks.mailtoEncoded("line\nnext") == "line%0Anext")
        #expect(SupportLinks.mailtoEncoded("año") == "a%C3%B1o")
        #expect(SupportLinks.mailtoEncoded("A-z_0.9~") == "A-z_0.9~")
    }

    @Test func theCurrentDetailsAreFilledIn() {
        let current = SystemDetails.current()

        #expect(!current.systemVersion.isEmpty)
        #expect(!current.macModel.isEmpty)
        #expect(current.lines.count == 3)
    }
}

struct DiagnosticReportStoreTests {
    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "PastoDiagnostics-\(UUID().uuidString)", directoryHint: .isDirectory)

    private func setAge(of url: URL, days: Double, now: Date) throws {
        try FileManager.default.setAttributes(
            [.modificationDate: now.addingTimeInterval(-days * 24 * 60 * 60)], ofItemAtPath: url.path
        )
    }

    @Test func savesEachFileUnderItsOwnName() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticReportStore(directory: directory)
        let date = Date(timeIntervalSince1970: 1_800_000_000)

        let first = try store.save(Data("{}".utf8), as: .report, at: date)
        let second = try store.save(Data("{}".utf8), as: .report, at: date)
        let log = try store.save(Data("entries".utf8), as: .log, at: date)

        #expect(first.lastPathComponent.hasPrefix("report-"))
        #expect(first.pathExtension == "json")
        #expect(second != first)
        #expect(log.pathExtension == "txt")
        #expect(Set(store.files().map(\.lastPathComponent)) == Set([first, second, log].map(\.lastPathComponent)))
        #expect(store.files(of: [.log]).map(\.lastPathComponent) == [log.lastPathComponent])
    }

    /// The folder also holds what suggestions log; pruning never touches it.
    @Test func pruningKeepsTheNewestAndLeavesOtherFilesAlone() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticReportStore(directory: directory)
        let now = Date()

        let old = try store.save(Data("{}".utf8), as: .report, at: now.addingTimeInterval(-1))
        try setAge(of: old, days: 31, now: now)
        var recent: [URL] = []
        for index in 0..<(DiagnosticReportStore.maximumFileCount + 2) {
            let url = try store.save(Data("{}".utf8), as: .report, at: now.addingTimeInterval(Double(index)))
            try setAge(of: url, days: Double(index) / 10, now: now)
            recent.append(url)
        }
        let suggestions = directory.appending(path: "suggestion-log.jsonl")
        try Data("{}".utf8).write(to: suggestions)
        try setAge(of: suggestions, days: 60, now: now)

        store.prune(now: now)

        #expect(store.files().map(\.lastPathComponent) == recent.prefix(DiagnosticReportStore.maximumFileCount).map(\.lastPathComponent))
        #expect(FileManager.default.fileExists(atPath: suggestions.path))
    }

    /// Launch reports are the store's; the record of the running launch next to them is not.
    @Test func launchReportsAreListedAndTheLaunchRecordIsLeftAlone() throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = DiagnosticReportStore(directory: directory)
        let now = Date()
        let record = LaunchRecordStore(directory: directory)
        try record.save(LaunchRecord(processIdentifier: 1, version: "1.0", startedAt: now, wasLaunchedAsLoginItem: false, location: "applications"))
        try setAge(of: record.url, days: 60, now: now)

        let report = try store.save(Data("{}".utf8), as: .launch, at: now)
        store.prune(now: now)

        #expect(report.lastPathComponent.hasPrefix("launch-"))
        #expect(store.files().map(\.lastPathComponent) == [report.lastPathComponent])
        #expect(FileManager.default.fileExists(atPath: record.url.path))
    }
}
