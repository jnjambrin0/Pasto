import Foundation

/// Which copy of Pasto goes on when another copy with the same bundle identifier is already
/// running. Two copies would capture every copy twice, fight over the shortcuts and open the
/// same store.
///
/// The older copy always stays: the younger one waits a moment — a copy that has just moved
/// itself to Applications, or that an update replaces, quits on its own — and then gives way.
/// Comparing launch times means two copies started at once cannot both give way, or both stay.
public nonisolated enum SingleInstancePolicy {
    /// A running copy, as far as the decision needs to know it.
    public struct Copy: Sendable, Equatable {
        public let processIdentifier: Int32
        /// Nil when the system does not say.
        public let launchDate: Date?
        /// The short version, `1.0.2`; nil when unknown.
        public let version: String?
        /// Its launch record says it has been stuck in a phase for longer than that phase's limit.
        public let isStuckLaunching: Bool

        public init(processIdentifier: Int32, launchDate: Date?, version: String?, isStuckLaunching: Bool = false) {
            self.processIdentifier = processIdentifier
            self.launchDate = launchDate
            self.version = version
            self.isStuckLaunching = isStuckLaunching
        }
    }

    /// What the copy that is starting does once the older copies have had their moment to quit.
    public enum Decision: Equatable, Sendable {
        /// No older copy is running: go on.
        case proceed
        /// The older copy is stuck in its launch: make it quit, then go on.
        case replaceStuckCopy(Int32)
        /// This copy is a newer version that has to be moved into Applications: go on, so that
        /// moving it offers to replace the copy that is running.
        case proceedToReplace(Int32)
        /// Bring the older copy forward and quit.
        case handOver(to: Int32)
    }

    /// Whether `other` started before `me`. The system's launch dates decide; a copy without
    /// one counts as the older, and equal dates go by process identifier.
    public static func isOlder(_ other: Copy, than me: Copy) -> Bool {
        switch (other.launchDate, me.launchDate) {
        case let (otherDate?, myDate?) where otherDate != myDate:
            otherDate < myDate
        case (nil, .some):
            true
        case (.some, nil):
            false
        default:
            other.processIdentifier < me.processIdentifier
        }
    }

    /// The copies `me` has to settle with: those that started before it. A younger copy settles
    /// with `me` itself.
    public static func olderCopies(than me: Copy, among others: [Copy]) -> [Copy] {
        others.filter { $0.processIdentifier != me.processIdentifier && isOlder($0, than: me) }
    }

    /// The decision once the older copies have had their moment to quit.
    ///
    /// - Parameters:
    ///   - stillRunning: The older copies that are still running.
    ///   - needsRelocation: This copy runs from somewhere it should be moved from.
    public static func decision(for me: Copy, olderCopiesStillRunning stillRunning: [Copy], needsRelocation: Bool) -> Decision {
        let older = olderCopies(than: me, among: stillRunning)
        // The oldest is the one that holds the shortcuts and the store.
        guard let oldest = older.min(by: { isOlder($0, than: $1) }) else { return .proceed }
        if oldest.isStuckLaunching {
            return .replaceStuckCopy(oldest.processIdentifier)
        }
        if needsRelocation, isNewer(me.version, than: oldest.version) {
            return .proceedToReplace(oldest.processIdentifier)
        }
        return .handOver(to: oldest.processIdentifier)
    }

    /// Whether version `a` is later than `b`, comparing their numbers; an unknown version is
    /// never later than anything.
    public static func isNewer(_ a: String?, than b: String?) -> Bool {
        guard let a, let b else { return false }
        return a.compare(b, options: .numeric) == .orderedDescending
    }
}
