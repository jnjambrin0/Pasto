import Foundation

/// Every failure a probe can report, mapped onto the tool's exit codes.
public enum ProbeError: Error, Equatable, Sendable {
    /// Bad command line (exit 1).
    case usage(String)
    /// A privacy permission is missing (exit 2).
    case permission(String)
    /// The app, window, display or file to measure does not exist (exit 3).
    case targetNotFound(String)
    /// Anything that went wrong while measuring (exit 4).
    case runtime(String)

    public var exitCode: Int32 {
        switch self {
        case .usage: 1
        case .permission: 2
        case .targetNotFound: 3
        case .runtime: 4
        }
    }

    public var message: String {
        switch self {
        case .usage(let text), .permission(let text), .targetNotFound(let text), .runtime(let text): text
        }
    }
}
