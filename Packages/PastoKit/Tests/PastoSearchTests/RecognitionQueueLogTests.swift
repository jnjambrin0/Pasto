import Foundation
import PastoCore
@testable import PastoSearch
import Testing

/// The queue of images to read is written once and read off by moving a cursor.
struct RecognitionQueueLogTests {
    private let folder = EphemeralDefaults()
    private var url: URL { folder.directory.appending(path: "queue.txt") }

    private func ids(_ names: String...) -> [ItemID] {
        names.map(ItemID.init(rawValue:))
    }

    @Test func whatIsReadIsNotReadAgainAndTheRestComesBackInOrder() {
        let log = RecognitionQueueLog(url: url)
        #expect(log.restore().isEmpty)
        log.append(ids("a", "b", "c"))
        log.finish(ItemID(rawValue: "a"))
        log.append(ids("d"))

        #expect(RecognitionQueueLog(url: url).restore() == ids("b", "c", "d"))
    }

    @Test func readingOnlyRewritesTheCursor() throws {
        let log = RecognitionQueueLog(url: url)
        _ = log.restore()
        log.append(ids("a", "b"))
        let before = try Data(contentsOf: url)
        log.finish(ItemID(rawValue: "a"))
        let after = try Data(contentsOf: url)

        #expect(after.count == before.count)
        #expect(after.dropFirst(16) == before.dropFirst(16))
        #expect(String(decoding: after.prefix(17), as: UTF8.self) == "0000000000000001\n")
    }

    @Test func anItemThatLeftTheQueueComesBackOnlyIfItWasBeforeTheCursor() {
        let log = RecognitionQueueLog(url: url)
        _ = log.restore()
        log.append(ids("a", "b", "c"))
        // "b" was deleted: forgotten without moving the cursor, it comes back after a relaunch
        // and is skipped then. Reading "c" moves the cursor past it.
        log.forget(ItemID(rawValue: "b"))
        #expect(RecognitionQueueLog(url: url).restore() == ids("a", "b", "c"))
        log.finish(ItemID(rawValue: "a"))
        log.finish(ItemID(rawValue: "c"))
        #expect(RecognitionQueueLog(url: url).restore().isEmpty)
    }

    @Test func aLineCutShortByAStopIsIgnoredAndAnEmptyQueueLeavesNoFile() throws {
        let log = RecognitionQueueLog(url: url)
        _ = log.restore()
        log.append(ids("a"))
        let handle = try FileHandle(forWritingTo: url)
        try handle.seekToEnd()
        try handle.write(contentsOf: Data("half-writ".utf8))
        try handle.close()
        #expect(RecognitionQueueLog(url: url).restore() == ids("a"))

        log.clear()
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(RecognitionQueueLog(url: url).restore().isEmpty)
    }

    @Test func writingBeforeReadingKeepsWhatWasSaved() {
        RecognitionQueueLog(url: url).append(ids("a"))
        // A log that has not read the file yet appends to it rather than starting it again.
        RecognitionQueueLog(url: url).append(ids("b"))
        #expect(RecognitionQueueLog(url: url).restore() == ids("a", "b"))
    }
}
