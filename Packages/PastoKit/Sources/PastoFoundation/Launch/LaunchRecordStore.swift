import Foundation

/// Where the running copy keeps its launch record: `last-launch.json`, next to the diagnostic
/// reports. One file, rewritten at each phase; every copy with the same bundle identifier shares
/// it, which is how a copy started later can tell that the one already running is stuck.
public nonisolated struct LaunchRecordStore: Sendable {
    public let directory: URL

    public init(directory: URL = DiagnosticReportStore.defaultDirectory) {
        self.directory = directory
    }

    public var url: URL { directory.appending(path: "last-launch.json", directoryHint: .notDirectory) }

    /// The record on disk, or nil when there is none or it cannot be read.
    public func load() -> LaunchRecord? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(LaunchRecord.self, from: data)
    }

    /// Replaces the record on disk, whole or not at all.
    public func save(_ record: LaunchRecord) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(record).write(to: url, options: .atomic)
    }
}
