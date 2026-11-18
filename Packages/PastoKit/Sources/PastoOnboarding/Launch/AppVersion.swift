import Foundation

/// A version of the app, as written in the bundle: "1.2" or "1.2.3".
public nonisolated struct AppVersion: Hashable, Comparable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int = 0, patch: Int = 0) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    /// Nil unless the text is one to three whole numbers separated by dots.
    public init?(_ text: String) {
        let parts = text.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard (1...3).contains(parts.count), let numbers = parts as? [Int], numbers.allSatisfy({ $0 >= 0 }) else {
            return nil
        }
        self.init(major: numbers[0], minor: numbers.count > 1 ? numbers[1] : 0, patch: numbers.count > 2 ? numbers[2] : 0)
    }

    /// The version of the running app.
    public init?(bundle: Bundle) {
        guard let text = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String else { return nil }
        self.init(text)
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}
