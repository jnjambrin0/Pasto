import Foundation

/// A launch that did not go as it should, written to the diagnostics folder as
/// `launch-<date>.json` for the user to attach to a report. Like the record it carries, it holds
/// nothing of the user's.
public nonisolated struct LaunchReport: Codable, Sendable, Equatable {
    public enum Kind: String, Codable, Sendable {
        /// This launch has been in one phase for longer than the phase's limit.
        case stalled
        /// The previous launch went away before it was ready, without quitting: it crashed, was
        /// killed, or was a stuck copy the next one made quit.
        case previousLaunchInterrupted
    }

    public let kind: Kind
    public let record: LaunchRecord
    /// How long the launch had been in its phase when the report was written; for a previous
    /// launch, as long as its record says.
    public let secondsInPhase: TimeInterval?
    /// How long the main thread had gone without answering, when known: a long silence means it
    /// was blocked (opening the store, a deadlock) rather than waiting.
    public let mainThreadSilence: TimeInterval?
    /// `macOS 27.2 (Build 27C…)`.
    public let system: String

    public init(
        kind: Kind,
        record: LaunchRecord,
        secondsInPhase: TimeInterval? = nil,
        mainThreadSilence: TimeInterval? = nil,
        system: String = ProcessInfo.processInfo.operatingSystemVersionString
    ) {
        self.kind = kind
        self.record = record
        self.secondsInPhase = secondsInPhase.map(Self.rounded)
        self.mainThreadSilence = mainThreadSilence.map(Self.rounded)
        self.system = system
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Tenths of a second are enough to read a report.
    private static func rounded(_ seconds: TimeInterval) -> TimeInterval {
        (seconds * 10).rounded() / 10
    }
}
