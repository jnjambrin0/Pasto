import Foundation

/// A `UserDefaults` suite of its own for one test, gone when the test ends.
///
/// The suite is named with a path, which makes the preferences system keep its file there instead
/// of in `~/Library/Preferences` — where removing a domain still leaves an empty file behind.
nonisolated final class EphemeralDefaults {
    let defaults: UserDefaults
    private let directory: URL
    private let suiteName: String

    init() {
        directory = FileManager.default.temporaryDirectory.appending(path: "PastoTests-\(UUID().uuidString)")
        suiteName = directory.appending(path: "defaults").path
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = UserDefaults(suiteName: suiteName)!
    }

    deinit {
        defaults.removePersistentDomain(forName: suiteName)
        try? FileManager.default.removeItem(at: directory)
    }
}
