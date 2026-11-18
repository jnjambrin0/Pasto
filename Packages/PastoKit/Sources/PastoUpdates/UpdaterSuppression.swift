import Foundation

/// Why Pasto does not look for updates on this run. Development builds and runs never do, and a
/// build whose Info.plist lacks the feed or the key that verifies updates cannot: Sparkle would
/// only greet the user with an error.
public enum UpdaterSuppression: Equatable, Sendable {
    /// A Debug build: signed for development and replaced by every rebuild.
    case debugBuild
    /// A run with the store in memory (`--in-memory-store`, `--synthetic-items`).
    case developmentRun
    /// `SUFeedURL` is missing, empty or not an https URL.
    case missingFeedURL
    /// `SUPublicEDKey` is missing or empty: every update would be rejected.
    case missingPublicKey

    /// - Returns: `nil` when the updater may start.
    public static func reason(
        infoDictionary: [String: Any],
        isDebugBuild: Bool,
        isDevelopmentRun: Bool
    ) -> UpdaterSuppression? {
        if isDebugBuild { return .debugBuild }
        if isDevelopmentRun { return .developmentRun }
        guard let feed = text(infoDictionary["SUFeedURL"]), URL(string: feed)?.scheme == "https" else {
            return .missingFeedURL
        }
        guard text(infoDictionary["SUPublicEDKey"]) != nil else { return .missingPublicKey }
        return nil
    }

    private static func text(_ value: Any?) -> String? {
        guard let string = (value as? String)?.trimmingCharacters(in: .whitespacesAndNewlines), !string.isEmpty else {
            return nil
        }
        return string
    }
}
