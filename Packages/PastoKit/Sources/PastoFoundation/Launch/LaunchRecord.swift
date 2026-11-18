import Foundation

/// What one launch of Pasto went through, phase by phase. The running copy keeps it on disk as
/// it goes, so the next launch — or another copy started meanwhile — can tell how this one
/// ended: ready, quit, or stopped half-way.
///
/// It holds nothing of the user's: process, version, times, phases and the kind of place the
/// app runs from.
public nonisolated struct LaunchRecord: Codable, Sendable, Equatable {
    /// A phase and when it started, in seconds since the launch.
    public struct Step: Codable, Sendable, Equatable {
        public let phase: LaunchPhase
        public let seconds: TimeInterval

        public init(phase: LaunchPhase, seconds: TimeInterval) {
            self.phase = phase
            self.seconds = seconds
        }
    }

    /// How a launch ended, as seen once it is over.
    public enum Ending: Equatable, Sendable {
        /// It got to `ready`; whatever happened later is not the launch's doing.
        case ready
        /// The app quit before it was ready: the user quit, or the copy gave way to another.
        case quit(during: LaunchPhase)
        /// The process went away before it was ready, without quitting: it crashed, or was
        /// killed — by the user, because nothing seemed to happen, or by the system.
        case interrupted(during: LaunchPhase)
    }

    public let processIdentifier: Int32
    /// `1.0.2 (3)`: the short version and the build.
    public let version: String
    public let startedAt: Date
    public let wasLaunchedAsLoginItem: Bool
    /// The kind of place the app runs from (`applications`, `diskImage`, `translocated`,
    /// `outsideApplications`), never the path.
    public let location: String
    public private(set) var steps: [Step]
    /// Set as the app quits.
    public private(set) var didQuit = false

    public init(
        processIdentifier: Int32,
        version: String,
        startedAt: Date,
        wasLaunchedAsLoginItem: Bool,
        location: String
    ) {
        self.processIdentifier = processIdentifier
        self.version = version
        self.startedAt = startedAt
        self.wasLaunchedAsLoginItem = wasLaunchedAsLoginItem
        self.location = location
        steps = [Step(phase: .started, seconds: 0)]
    }

    /// The phase the launch is in.
    public var phase: LaunchPhase { steps.last?.phase ?? .started }

    /// When the current phase started.
    public var phaseStartedAt: Date {
        startedAt.addingTimeInterval(steps.last?.seconds ?? 0)
    }

    public var isReady: Bool { steps.contains { $0.phase == .ready } }

    /// Records that the launch moved on to `phase` at `date`. Once ready, the launch is over and
    /// nothing more is recorded; entering the phase it is already in changes nothing.
    public mutating func enter(_ phase: LaunchPhase, at date: Date) {
        guard !isReady, phase != self.phase else { return }
        steps.append(Step(phase: phase, seconds: max(0, date.timeIntervalSince(startedAt))))
    }

    public mutating func markQuit() {
        didQuit = true
    }

    /// How long the launch has been in its current phase at `now`.
    public func secondsInPhase(at now: Date) -> TimeInterval {
        max(0, now.timeIntervalSince(phaseStartedAt))
    }

    /// Whether the launch has been in a phase that does not wait for the user for longer than
    /// that phase's limit. A launch that is ready, or that quit, is never stalled.
    public func isStalled(at now: Date) -> Bool {
        guard !isReady, !didQuit, let limit = phase.stallLimit else { return false }
        return secondsInPhase(at: now) > limit
    }

    /// How the launch ended, for a launch whose process is gone.
    public var ending: Ending {
        if isReady { return .ready }
        return didQuit ? .quit(during: phase) : .interrupted(during: phase)
    }
}
