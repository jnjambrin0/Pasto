import os

/// Unified logging for Pasto. One `Logger` per subsystem area so `log stream` can be filtered
/// with `--predicate 'subsystem == "jnjambrino.Pasto" && category == "pasteboard"'`.
public enum Log {
    /// The running app's bundle identifier (`AppIdentity`): `jnjambrino.Pasto` for the published
    /// app, another one for a build that declares its own.
    public static let subsystem = AppIdentity.bundleIdentifier

    public enum Category: String, CaseIterable, Sendable {
        case app
        case pasteboard
        case store
        case panel
        case paste
        case shortcut
        case search
        case picks
        case updates
    }

    public static func logger(_ category: Category) -> Logger {
        Logger(subsystem: subsystem, category: category.rawValue)
    }
}
