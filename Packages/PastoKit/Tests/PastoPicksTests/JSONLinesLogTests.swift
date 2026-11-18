import Foundation
@testable import PastoPicks
import Testing

struct JSONLinesLogTests {
    struct Entry: Codable, Sendable, Equatable {
        var name: String
        var date: Date
    }

    private let directory = FileManager.default.temporaryDirectory
        .appending(path: "PastoPicksTests-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var url: URL { directory.appending(path: "Nested/log.jsonl") }

    @Test func appendingCreatesTheFolderAndKeepsTheOrder() async throws {
        defer { cleanUp() }
        let log = JSONLinesLog<Entry>(url: url, limit: .count(10))
        try await log.append(entry("a", at: 1))
        try await log.append(entry("b", at: 2))
        #expect(try await log.entries().map(\.name) == ["a", "b"])
    }

    @Test func aMissingFileReadsAsEmpty() async throws {
        let log = JSONLinesLog<Entry>(url: url, limit: .count(10))
        #expect(try await log.entries().isEmpty)
    }

    @Test func linesHaveSortedKeysAndDatesInSeconds() async throws {
        defer { cleanUp() }
        let log = JSONLinesLog<Entry>(url: url, limit: .count(10))
        try await log.append(entry("a", at: 12))
        let content = try String(contentsOf: url, encoding: .utf8)
        #expect(content == #"{"date":12,"name":"a"}"# + "\n")
    }

    @Test func entriesOlderThanTheAgeLimitGoWhenOneIsAdded() async throws {
        defer { cleanUp() }
        let earlier = JSONLinesLog<Entry>(url: url, limit: .age(100, date: \.date), now: { Date(timeIntervalSinceReferenceDate: 900) })
        try await earlier.append(entry("old", at: 850))
        try await earlier.append(entry("recent", at: 950))

        let later = JSONLinesLog<Entry>(url: url, limit: .age(100, date: \.date), now: { Date(timeIntervalSinceReferenceDate: 1000) })
        // Reading does not apply the limit.
        #expect(try await later.entries().count == 2)
        try await later.append(entry("new", at: 1000))
        #expect(try await later.entries().map(\.name) == ["recent", "new"])
    }

    @Test func onlyTheNewestEntriesStayWithinTheCount() async throws {
        defer { cleanUp() }
        let log = JSONLinesLog<Entry>(url: url, limit: .count(3))
        for index in 0..<5 {
            try await log.append(entry("\(index)", at: index))
        }
        #expect(try await log.entries().map(\.name) == ["2", "3", "4"])
    }

    @Test func aLastLineWithoutABreakIsCompletedBeforeAppending() async throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(#"{"date":1,"name":"a"}"#.utf8).write(to: url)
        let log = JSONLinesLog<Entry>(url: url, limit: .count(10))
        try await log.append(entry("b", at: 2))
        #expect(try await log.entries().map(\.name) == ["a", "b"])
    }

    @Test func unreadableLinesAreSkippedAndKeptUntilTheFileIsRewritten() async throws {
        defer { cleanUp() }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("not json\n{\"date\":1,\"name\":\"a\"}\n".utf8).write(to: url)
        let log = JSONLinesLog<Entry>(url: url, limit: .count(2))
        #expect(try await log.entries().map(\.name) == ["a"])
        // Nothing readable is dropped: the new line is only added.
        try await log.append(entry("b", at: 2))
        #expect(try String(contentsOf: url, encoding: .utf8).contains("not json"))
        // Over the limit the file is rewritten, without what could not be read.
        try await log.append(entry("c", at: 3))
        #expect(!(try String(contentsOf: url, encoding: .utf8).contains("not json")))
        #expect(try await log.entries().map(\.name) == ["b", "c"])
    }

    @Test func erasingDeletesTheFileAndToleratesItsAbsence() async throws {
        defer { cleanUp() }
        let log = JSONLinesLog<Entry>(url: url, limit: .count(10))
        try await log.append(entry("a", at: 1))
        try await log.erase()
        #expect(!FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
        try await log.erase()
    }

    private func entry(_ name: String, at seconds: Int) -> Entry {
        Entry(name: name, date: Date(timeIntervalSinceReferenceDate: TimeInterval(seconds)))
    }

    private func cleanUp() {
        try? FileManager.default.removeItem(at: directory)
    }
}
