import Foundation

/// Pasto's own diagnostic files, kept on this Mac: the crash and hang reports macOS hands over
/// through MetricKit, and the log of a session that the user saves to report a problem. Nothing
/// is ever sent; the user may attach them to a report.
///
/// The folder is shared with what suggestions log (`suggestion-log.jsonl`) and with the record
/// of the running launch (`last-launch.json`, `LaunchRecordStore`): only files named
/// `report-…json`, `launch-…json` and `log-…txt` are this store's.
public nonisolated struct DiagnosticReportStore: Sendable {
    public enum Kind: String, Sendable {
        /// A MetricKit diagnostic payload, as JSON.
        case report
        /// Pasto's log entries of one session, as text.
        case log
        /// A launch that stalled or never got to be ready (`LaunchReport`), as JSON.
        case launch

        var fileExtension: String {
            switch self {
            case .report, .launch: "json"
            case .log: "txt"
            }
        }
    }

    /// `Diagnostics` in Pasto's folder in Application Support.
    public static var defaultDirectory: URL {
        AppIdentity.applicationSupportDirectory.appending(path: "Diagnostics", directoryHint: .isDirectory)
    }

    /// Files older than this go when the store is pruned.
    public static let retention: TimeInterval = 30 * 24 * 60 * 60
    /// At most this many files of each kind are kept, the newest.
    public static let maximumFileCount = 20

    public let directory: URL

    public init(directory: URL = Self.defaultDirectory) {
        self.directory = directory
    }

    /// Writes `data` as a new file of `kind`, named after `date` (local time), and returns it.
    @discardableResult
    public func save(_ data: Data, as kind: Kind, at date: Date) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let stem = "\(kind.rawValue)-\(Self.timestamp(date))"
        var url = directory.appending(path: "\(stem).\(kind.fileExtension)")
        var copy = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = directory.appending(path: "\(stem)-\(copy).\(kind.fileExtension)")
            copy += 1
        }
        try data.write(to: url, options: .withoutOverwriting)
        return url
    }

    /// The store's files, newest first.
    public func files(of kinds: Set<Kind> = [.report, .launch, .log]) -> [URL] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.contentModificationDateKey]
        )) ?? []
        return urls
            .filter { url in kinds.contains { Self.isFile(url, of: $0) } }
            .map { (url: $0, date: Self.modificationDate(of: $0)) }
            .sorted { $0.date > $1.date }
            .map(\.url)
    }

    /// Deletes the files older than `retention`, and of each kind those beyond the newest
    /// `maximumFileCount`. Other files in the folder are left alone.
    public func prune(now: Date = Date()) {
        for kind in [Kind.report, .launch, .log] {
            for (position, url) in files(of: [kind]).enumerated()
            where position >= Self.maximumFileCount || now.timeIntervalSince(Self.modificationDate(of: url)) > Self.retention {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    static func isFile(_ url: URL, of kind: Kind) -> Bool {
        url.lastPathComponent.hasPrefix("\(kind.rawValue)-") && url.pathExtension == kind.fileExtension
    }

    private static func modificationDate(of url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd-HHmmss"
        return formatter.string(from: date)
    }
}
