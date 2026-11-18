import Foundation

/// Where the running copy of Pasto is, and whether that place lets it work as it should. A
/// login item registered from a copy that goes away points at nothing, and the updater cannot
/// replace a copy on a read-only volume.
public nonisolated struct ApplicationLocation: Equatable, Sendable {
    public enum Problem: Equatable, Sendable {
        /// macOS runs a downloaded app the user has not moved from a randomised, read-only
        /// mirror of it (App Translocation), gone once the Mac restarts.
        case translocated
        /// A disk image or another read-only volume.
        case readOnlyVolume
        /// A writable folder outside `/Applications` and `~/Applications`, such as Downloads.
        case outsideApplications
    }

    public let bundleURL: URL
    public let isOnReadOnlyVolume: Bool
    /// Nil when the copy is in an Applications folder, or below one.
    public let problem: Problem?

    public init(bundleURL: URL, isOnReadOnlyVolume: Bool, homeDirectory: URL) {
        self.bundleURL = bundleURL
        self.isOnReadOnlyVolume = isOnReadOnlyVolume
        if bundleURL.standardizedFileURL.path.contains("/AppTranslocation/") {
            problem = .translocated
        } else if isOnReadOnlyVolume {
            problem = .readOnlyVolume
        } else if !Self.isInApplicationsFolder(bundleURL, homeDirectory: homeDirectory) {
            problem = .outsideApplications
        } else {
            problem = nil
        }
    }

    /// Whether the copy goes away when the disk image is ejected or the Mac restarts: nothing
    /// that outlives the launch (a login item, an update) can be pinned to it.
    public var isEphemeral: Bool {
        problem == .translocated || problem == .readOnlyVolume
    }

    /// The running copy, as it is now.
    public static func current() -> ApplicationLocation {
        let bundleURL = Bundle.main.bundleURL
        return ApplicationLocation(
            bundleURL: bundleURL,
            isOnReadOnlyVolume: isOnReadOnlyVolume(bundleURL),
            homeDirectory: FileManager.default.homeDirectoryForCurrentUser
        )
    }

    public static func isOnReadOnlyVolume(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
    }

    /// `/Applications`, and the user's own `~/Applications`.
    public static func applicationsFolders(homeDirectory: URL) -> (system: URL, user: URL) {
        (URL(filePath: "/Applications", directoryHint: .isDirectory), homeDirectory.appending(path: "Applications", directoryHint: .isDirectory))
    }

    /// Inside either Applications folder, at any depth (`/Applications/Utilities/…` counts).
    static func isInApplicationsFolder(_ url: URL, homeDirectory: URL) -> Bool {
        let components = url.standardizedFileURL.pathComponents
        let folders = applicationsFolders(homeDirectory: homeDirectory)
        return [folders.system, folders.user].contains { folder in
            let folderComponents = folder.standardizedFileURL.pathComponents
            return components.count > folderComponents.count && components.starts(with: folderComponents)
        }
    }
}

/// How a copy of Pasto in the wrong place gets into an Applications folder: what is copied
/// where, and what is left in the Trash. Doing it is `ApplicationRelocator`'s, in `PastoApp`.
public nonisolated struct ApplicationRelocation: Equatable, Sendable {
    /// What is copied: the running bundle. For a translocated app that is its mirror, which
    /// holds the same files as the user's copy.
    public let source: URL
    /// Where Pasto ends up, and is opened from.
    public let destination: URL
    /// The copy the user downloaded, moved to the Trash once the new one is in place; nil when
    /// it is on a read-only volume such as a disk image.
    public let originalToTrash: URL?
    /// False when the user's copy already is in an Applications folder, and only the
    /// quarantine mark kept it translocated: nothing is copied, the mark is taken off it.
    public let copiesBundle: Bool

    /// - Parameters:
    ///   - translocatedOriginal: For a translocated copy, where the user's copy really is and
    ///     whether that is a read-only volume; nil when macOS would not say.
    ///   - isSystemApplicationsFolderWritable: Whether this user can write in `/Applications`;
    ///     if not, Pasto goes to `~/Applications`.
    /// - Returns: Nil when there is nothing to move, or no way to know what to move: a
    ///   translocated copy whose original macOS would not give.
    public static func plan(
        for location: ApplicationLocation,
        translocatedOriginal: (url: URL, isOnReadOnlyVolume: Bool)?,
        isSystemApplicationsFolderWritable: Bool,
        homeDirectory: URL
    ) -> ApplicationRelocation? {
        guard let problem = location.problem else { return nil }
        let original: (url: URL, isOnReadOnlyVolume: Bool)
        if problem == .translocated {
            guard let translocatedOriginal else { return nil }
            original = translocatedOriginal
            if ApplicationLocation.isInApplicationsFolder(original.url, homeDirectory: homeDirectory) {
                return ApplicationRelocation(source: original.url, destination: original.url, originalToTrash: nil, copiesBundle: false)
            }
        } else {
            original = (location.bundleURL, location.isOnReadOnlyVolume)
        }
        let folders = ApplicationLocation.applicationsFolders(homeDirectory: homeDirectory)
        let folder = isSystemApplicationsFolderWritable ? folders.system : folders.user
        return ApplicationRelocation(
            source: location.bundleURL,
            destination: folder.appending(path: original.url.lastPathComponent, directoryHint: .isDirectory),
            originalToTrash: original.isOnReadOnlyVolume ? nil : original.url,
            copiesBundle: true
        )
    }
}
