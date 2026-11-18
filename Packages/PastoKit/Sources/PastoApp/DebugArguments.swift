import Foundation

/// Launch arguments for development and measurement (docs/DEVELOPMENT.md).
/// They let scripts put the app in a known state without synthetic key presses.
///
/// Only Debug builds read them. A Release build ignores its arguments: none of these can skip
/// onboarding, keep the history away from the store or write files for a user.
enum DebugArguments {
    #if DEBUG
    private static let arguments = ProcessInfo.processInfo.arguments

    /// `--show-panel`: open the clipboard panel as soon as the app has launched.
    static var showsPanelAtLaunch: Bool {
        arguments.contains("--show-panel")
    }

    /// `--in-memory-store`: keep the history in memory, leaving the user's store untouched.
    /// Implied by `--synthetic-items`.
    static var usesInMemoryStore: Bool {
        arguments.contains("--in-memory-store") || syntheticItemCount != nil
    }

    /// `--synthetic-items <count>`: start with that many generated text items, for scale tests.
    static var syntheticItemCount: Int? {
        value(after: "--synthetic-items").flatMap(Int.init).map { max($0, 0) }
    }

    /// `--frame-log <path>`: append one line per second with frame pacing statistics.
    static var frameLogURL: URL? {
        value(after: "--frame-log").map { URL(fileURLWithPath: $0) }
    }

    private static func value(after flag: String) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
    #else
    static let showsPanelAtLaunch = false
    static let usesInMemoryStore = false
    static let syntheticItemCount: Int? = nil
    static let frameLogURL: URL? = nil
    #endif
}
