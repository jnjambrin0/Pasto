import Darwin
import Foundation

/// Keeps a folder and everything in it to the user alone: folders `0700`, files `0600`.
///
/// For Pasto's folder in Application Support, which holds the clipboard history (the store, its
/// external data, the suggestions journals). Another account on the Mac must not be able to read
/// it, whatever mode the files were created with: the folder's own mode is what keeps others
/// out, and the files get theirs as a second line.
public enum OwnerOnlyAccess {
    public static let directoryPermissions: mode_t = 0o700
    public static let filePermissions: mode_t = 0o600

    /// Creates `directory` if it is missing and restricts it and everything already in it.
    /// Symbolic links are neither followed nor changed. Call it before anything is written there.
    ///
    /// - Returns: How many folders and files had their mode changed.
    @discardableResult
    public static func restrict(_ directory: URL) throws -> Int {
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: directoryPermissions]
        )
        var changed = try restrict(path: directory.path(percentEncoded: false)) ? 1 : 0
        let keys: [URLResourceKey] = [.isSymbolicLinkKey]
        guard let contents = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else { return changed }
        for case let url as URL in contents {
            if (try? url.resourceValues(forKeys: Set(keys)).isSymbolicLink) == true { continue }
            if try restrict(path: url.path(percentEncoded: false)) {
                changed += 1
            }
        }
        return changed
    }

    /// Gives the folder or file at `path` its mode unless it already has it. Other kinds of
    /// entries (sockets, devices) are left alone.
    private static func restrict(path: String) throws -> Bool {
        var status = stat()
        guard lstat(path, &status) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        let target: mode_t
        switch status.st_mode & S_IFMT {
        case S_IFDIR: target = directoryPermissions
        case S_IFREG: target = filePermissions
        default: return false
        }
        guard status.st_mode & 0o7777 != target else { return false }
        guard chmod(path, target) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return true
    }
}
