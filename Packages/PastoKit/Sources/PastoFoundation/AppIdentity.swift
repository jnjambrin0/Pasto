import Foundation

/// Which Pasto this is. Its bundle identifier names its data folder, its log subsystem and its
/// search index, as it already names its preferences, its login item and its privacy
/// permissions — so a build with an identifier of its own (a development build as
/// `jnjambrino.Pasto.dev`) keeps everything apart from the published app.
public nonisolated enum AppIdentity {
    /// The identifier Pasto ships with. Code that does not run inside an app bundle — tests,
    /// command-line tools — goes by it.
    public static let defaultBundleIdentifier = "jnjambrino.Pasto"

    /// The running app's bundle identifier, or `defaultBundleIdentifier` outside an app bundle.
    public static let bundleIdentifier = bundleIdentifier(
        declared: Bundle.main.bundleIdentifier,
        bundleURL: Bundle.main.bundleURL
    )

    /// Pasto's folder in Application Support: the store, what suggestions learn, diagnostics.
    public static var applicationSupportDirectory: URL {
        URL.applicationSupportDirectory.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }

    /// - Parameters:
    ///   - declared: What the main bundle declares, if anything.
    ///   - bundleURL: Where the main bundle is; only an `.app` counts.
    static func bundleIdentifier(declared: String?, bundleURL: URL) -> String {
        guard bundleURL.pathExtension == "app", let declared, !declared.isEmpty else {
            return defaultBundleIdentifier
        }
        return declared
    }
}
