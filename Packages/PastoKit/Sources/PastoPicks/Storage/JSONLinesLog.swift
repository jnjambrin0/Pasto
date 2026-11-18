import Foundation

/// A file of JSON values, one per line, that grows at the end and forgets entries that are too
/// old or too many.
///
/// Adding an entry reads the file and drops what the limit no longer allows; the file is only
/// rewritten, atomically, when something was dropped, and otherwise just gets one more line.
/// Values are encoded with sorted keys and dates as seconds since the reference date.
actor JSONLinesLog<Entry: Codable & Sendable> {
    enum Limit: Sendable {
        /// Entries whose date is further back than this are dropped.
        case age(TimeInterval, date: @Sendable (Entry) -> Date)
        /// Only this many entries are kept, the newest ones.
        case count(Int)
    }

    let url: URL
    private let limit: Limit
    private let now: @Sendable () -> Date
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        return encoder
    }()
    private let decoder = JSONDecoder()

    init(url: URL, limit: Limit, now: @escaping @Sendable () -> Date = { Date() }) {
        self.url = url
        self.limit = limit
        self.now = now
    }

    /// Every entry in the file, oldest first, as it is: the limit is applied when adding, not
    /// when reading. A missing file reads as empty; a line that cannot be read is skipped.
    func entries() throws -> [Entry] {
        try lines().compactMap(decode)
    }

    /// Adds `entry` at the end, after dropping what the limit no longer allows. Lines that cannot
    /// be read stay until the file is next rewritten.
    func append(_ entry: Entry) throws {
        let entries = try lines().compactMap(decode)
        let kept = kept(entries)
        let line = try encoder.encode(entry)

        guard kept.count == entries.count else {
            let content = try (kept.map(encoder.encode) + [line]).map { $0 + newline }.reduce(Data(), +)
            try createDirectory()
            try content.write(to: url, options: .atomic)
            return
        }
        try appendLine(line)
    }

    /// Deletes the file. Nothing to delete is not an error.
    func erase() throws {
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
            return
        }
    }

    // MARK: -

    private var newline: Data { Data([0x0A]) }

    private func lines() throws -> [Data] {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
        return data.split(separator: 0x0A).map { Data($0) }
    }

    private func decode(_ line: Data) -> Entry? {
        try? decoder.decode(Entry.self, from: line)
    }

    private func kept(_ entries: [Entry]) -> [Entry] {
        switch limit {
        case .age(let maximumAge, let date):
            let cutoff = now().addingTimeInterval(-maximumAge)
            return entries.filter { date($0) >= cutoff }
        case .count(let capacity):
            // Room for the entry about to be added.
            return Array(entries.suffix(max(capacity - 1, 0)))
        }
    }

    /// Writes `line` at the end of the file, after a line break if the last line lacks one.
    private func appendLine(_ line: Data) throws {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else {
            try createDirectory()
            try (line + newline).write(to: url)
            return
        }
        let handle = try FileHandle(forUpdating: url)
        defer { try? handle.close() }
        let end = try handle.seekToEnd()
        var content = line + newline
        if end > 0 {
            try handle.seek(toOffset: end - 1)
            if try handle.read(upToCount: 1) != newline {
                content = newline + content
            }
        }
        try handle.seekToEnd()
        try handle.write(contentsOf: content)
    }

    private func createDirectory() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
}
