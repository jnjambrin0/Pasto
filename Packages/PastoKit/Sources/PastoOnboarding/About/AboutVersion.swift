/// The version the About window shows: the marketing version followed by the build in
/// parentheses, such as "1.2.0 (345)".
nonisolated enum AboutVersion {
    /// `nil` without a marketing version; just that version when the build is missing or empty.
    static func text(shortVersion: String?, build: String?) -> String? {
        guard let shortVersion, !shortVersion.isEmpty else { return nil }
        guard let build, !build.isEmpty else { return shortVersion }
        return "\(shortVersion) (\(build))"
    }
}
