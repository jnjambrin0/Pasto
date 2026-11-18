import Foundation

/// The files a store on disk is made of: the database, its write-ahead log and shared memory, and
/// the folder where Core Data keeps large values (`.<name>_SUPPORT`). Only together are they a
/// store, so whatever moves one moves them all.
struct StoreFiles {
    /// The database file.
    let url: URL

    var directory: URL { url.deletingLastPathComponent() }

    /// Every file of the set, whether it exists or not.
    var members: [URL] {
        let name = url.lastPathComponent
        let stem = url.deletingPathExtension().lastPathComponent
        return [
            url,
            directory.appending(path: "\(name)-wal", directoryHint: .notDirectory),
            directory.appending(path: "\(name)-shm", directoryHint: .notDirectory),
            directory.appending(path: ".\(stem)_SUPPORT", directoryHint: .isDirectory),
        ]
    }

    /// Copies the set into `folder`, which must not exist yet, keeping the names. On APFS the
    /// copies are clones: instant, and sharing their space until one side changes.
    func copy(into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        do {
            for file in existingMembers {
                try FileManager.default.copyItem(at: file, to: folder.appending(path: file.lastPathComponent))
            }
        } catch {
            try? FileManager.default.removeItem(at: folder)
            throw error
        }
    }

    /// Moves the set into `folder`, which must not exist yet, keeping the names: still a store
    /// that opens as it was.
    func move(into folder: URL) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: false)
        for file in existingMembers {
            try FileManager.default.moveItem(at: file, to: folder.appending(path: file.lastPathComponent))
        }
    }

    /// Replaces the set with the one `copy(into:)` saved in `folder`, and removes the folder.
    func restore(from folder: URL) throws {
        try remove()
        for file in StoreFiles(url: folder.appending(path: url.lastPathComponent)).existingMembers {
            try FileManager.default.moveItem(at: file, to: directory.appending(path: file.lastPathComponent))
        }
        try FileManager.default.removeItem(at: folder)
    }

    func remove() throws {
        for file in existingMembers {
            try FileManager.default.removeItem(at: file)
        }
    }

    private var existingMembers: [URL] {
        members.filter { FileManager.default.fileExists(atPath: $0.path) }
    }
}
