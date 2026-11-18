import Foundation

/// The folder that holds the temporary image copies: `<temporary directory>/images/`.
///
/// The copies are images of the history, so the folder is the user's alone (0700) and so is
/// every copy (0600); the application a copy is pasted into runs as the same user and reads it.
struct TemporaryImageDirectory: Sendable {
    static let directoryPermissions: Int16 = 0o700
    static let filePermissions: Int16 = 0o600

    let url: URL

    init(temporaryDirectory: URL) {
        url = temporaryDirectory.appending(path: RestoreMetrics.temporaryImagesDirectoryName, directoryHint: .isDirectory)
    }

    /// Writes `data` as `filename`, creating the folder if it is missing, and returns the file's
    /// URL. A file of that name left by an earlier paste is replaced.
    func write(_ data: Data, filename: String) throws -> URL {
        try prepare()
        let file = url.appending(path: filename, directoryHint: .notDirectory)
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: Self.filePermissions], ofItemAtPath: file.path(percentEncoded: false))
        return file
    }

    /// Deletes the copies created before `date`.
    ///
    /// Failures are ignored: what could not be read or deleted now is tried again by the clean-up
    /// of the next paste.
    func removeFiles(createdBefore date: Date) {
        let files = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: [.creationDateKey])) ?? []
        for file in files {
            guard let creationDate = try? file.resourceValues(forKeys: [.creationDateKey]).creationDate,
                  creationDate < date
            else { continue }
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Deletes every copy, and the folder with them. Nothing to delete is not an error.
    func removeAll() {
        try? FileManager.default.removeItem(at: url)
    }

    /// Creates the folder for the user alone, or makes an existing one so: a folder left by an
    /// earlier version keeps its mode through `createDirectory`.
    private func prepare() throws {
        let attributes: [FileAttributeKey: Any] = [.posixPermissions: Self.directoryPermissions]
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true, attributes: attributes)
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path(percentEncoded: false))
    }
}
