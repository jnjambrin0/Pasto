import Foundation
import PastoCore

/// Where the queue of images waiting for text recognition outlives the app.
///
/// A large history queues tens of thousands of images, read one every two seconds or so for
/// days. Keeping the queue in the settings would rewrite megabytes of them over and over. Here
/// every identifier is written once, appended to a file, and reading an image only moves a
/// cursor at the start of the file past it — sixteen bytes, written in place:
///
///     <cursor: 16 hexadecimal digits>\n
///     <item identifier>\n …
///
/// The cursor counts the lines dealt with. Images are read in the order they were queued
/// (`RecognitionQueue`), so everything before the line of the last image read has been read or
/// has left the queue — an item that was deleted stays in the file and is skipped when its turn
/// comes again after a relaunch. Once the queue is empty, the file is emptied too.
final class RecognitionQueueLog {
    private let url: URL
    /// The line of each queued identifier, for moving the cursor past it.
    private var lineByID: [ItemID: Int] = [:]
    private var lineCount = 0
    private var cursor = 0
    /// Whether the file has been read: nothing is written before, so as not to overwrite it.
    private var hasRead = false

    private static let cursorLength = 16

    init(url: URL) {
        self.url = url
    }

    /// The identifiers not yet dealt with, in the order they were queued. Reads the file once,
    /// when the indexer starts.
    func restore() -> [ItemID] {
        hasRead = true
        lineByID = [:]
        guard let contents = try? Data(contentsOf: url), contents.count > Self.cursorLength,
              let header = String(data: contents.prefix(Self.cursorLength), encoding: .ascii),
              let cursor = Int(header, radix: 16)
        else {
            lineCount = 0
            cursor = 0
            return []
        }
        // The last piece is empty after the final newline, or else a line the app stopped in
        // the middle of writing: either way not an identifier.
        let complete = contents.dropFirst(Self.cursorLength + 1)
            .split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: false)
            .dropLast()
        lineCount = complete.count
        if contents.last != UInt8(ascii: "\n"), let end = contents.lastIndex(of: UInt8(ascii: "\n")) {
            // Cut it off, so that the next identifier written does not run into it.
            try? FileHandle(forWritingTo: url).truncate(atOffset: UInt64(end + 1))
        }
        self.cursor = min(cursor, lineCount)
        var pending: [ItemID] = []
        for (line, bytes) in complete.enumerated() where line >= self.cursor {
            let id = ItemID(rawValue: String(decoding: bytes, as: UTF8.self))
            lineByID[id] = line
            pending.append(id)
        }
        return pending
    }

    /// Writes `ids` at the end of the file. Identifiers with a line break cannot be written,
    /// and no item has one.
    func append(_ ids: [ItemID]) {
        let ids = ids.filter { !$0.rawValue.contains("\n") }
        guard !ids.isEmpty else { return }
        if !hasRead {
            _ = restore()
        }
        var bytes = Data(ids.map { $0.rawValue + "\n" }.joined().utf8)
        do {
            if !FileManager.default.fileExists(atPath: url.path) || lineCount == 0 {
                bytes = Self.header(cursor: 0) + bytes
                try bytes.write(to: url, options: .atomic)
                lineCount = 0
                cursor = 0
            } else {
                let handle = try FileHandle(forWritingTo: url)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: bytes)
            }
            for id in ids {
                lineByID[id] = lineCount
                lineCount += 1
            }
        } catch {
            // Lost from the saved queue only: still read in this run.
        }
    }

    /// Moves the cursor past `id`, which has been dealt with.
    func finish(_ id: ItemID) {
        guard let line = lineByID.removeValue(forKey: id), line + 1 > cursor else { return }
        cursor = line + 1
        guard let handle = try? FileHandle(forWritingTo: url) else { return }
        defer { try? handle.close() }
        try? handle.seek(toOffset: 0)
        try? handle.write(contentsOf: Self.header(cursor: cursor).prefix(Self.cursorLength))
    }

    /// Forgets `id` without moving the cursor: it left the queue but may sit before images still
    /// to be read.
    func forget(_ id: ItemID) {
        lineByID[id] = nil
    }

    /// Empties the file: nothing is waiting.
    func clear() {
        lineByID = [:]
        guard lineCount > 0 else { return }
        lineCount = 0
        cursor = 0
        try? FileManager.default.removeItem(at: url)
    }

    private static func header(cursor: Int) -> Data {
        let digits = String(cursor, radix: 16)
        return Data((String(repeating: "0", count: max(0, cursorLength - digits.count)) + digits + "\n").utf8)
    }
}
