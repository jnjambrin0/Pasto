import Foundation

/// The change tokens `SystemPasteboard` keeps about the general pasteboard, and every rule that
/// moves them.
///
/// A token is a value of the pasteboard's change count. The tracker never touches the pasteboard:
/// it is told what was observed and answers what to do, which is what makes it testable.
struct PasteboardChangeTracker: Sendable {
    /// What one poll of the change count means.
    enum PollResult: Equatable, Sendable {
        case unchanged
        /// The change count moved: a read must be scheduled.
        case changed
        /// The change count is the one of a read that found the pasteboard empty. If the
        /// pasteboard has items by now, report it with `contentAppeared()` and schedule a read.
        case mayHaveBeenFilled
    }

    /// One read of the pasteboard.
    struct Read: Equatable, Sendable {
        /// The change count the read was made at.
        let token: Int
        /// How many changes it stands for: the distance to the last read that was not vetoed.
        let coveredChanges: Int
    }

    /// What a vetoed read leaves behind, so that the next one still counts the changes it covered.
    private struct DroppedSync: Equatable, Sendable {
        let token: Int
        let date: Date
    }

    /// The last change count a poll, a read or a write saw. A poll that finds another one has
    /// detected a change.
    private(set) var changeToken: Int
    /// The change count of the last read or write.
    private var synchronizedChangeToken: Int
    /// The change count Pasto's own last write produced.
    private var writtenChangeToken: Int?
    /// The change count of a read that found no items at all.
    private var emptyChangeToken: Int?
    private var droppedSyncBaseline: DroppedSync?

    /// How long a vetoed read keeps supplying the reference for the next one.
    private let droppedSyncWindow: TimeInterval

    init(changeToken: Int, droppedSyncWindow: TimeInterval) {
        self.changeToken = changeToken
        self.synchronizedChangeToken = changeToken
        self.droppedSyncWindow = droppedSyncWindow
    }

    /// Monitoring starts (or resumes): whatever is on the pasteboard now counts as seen.
    mutating func startMonitoring(changeCount: Int) {
        changeToken = changeCount
        synchronizedChangeToken = changeCount
        droppedSyncBaseline = nil
    }

    mutating func poll(changeCount: Int) -> PollResult {
        guard changeCount == changeToken else {
            changeToken = changeCount
            return .changed
        }
        return emptyChangeToken == changeCount ? .mayHaveBeenFilled : .unchanged
    }

    /// The pasteboard that was empty at the last read has items now, under the same change count
    /// (applications that clear first and write a moment later).
    mutating func contentAppeared() {
        emptyChangeToken = nil
    }

    /// A read begins at `changeCount`. It reads whatever is there, however the count got there.
    mutating func beginRead(changeCount: Int, at date: Date) -> Read {
        // A recent veto means the changes since the read before it have not been delivered yet.
        let reference: Int
        if let droppedSyncBaseline, date.timeIntervalSince(droppedSyncBaseline.date) <= droppedSyncWindow {
            reference = droppedSyncBaseline.token
        } else {
            reference = synchronizedChangeToken
        }
        droppedSyncBaseline = nil
        changeToken = changeCount
        synchronizedChangeToken = changeCount
        return Read(token: changeCount, coveredChanges: changeCount - reference)
    }

    /// The capture rules let `read` through. `isEmpty`: the pasteboard had no items at all.
    mutating func acceptRead(_ read: Read, isEmpty: Bool) {
        emptyChangeToken = isEmpty ? read.token : nil
    }

    /// The capture rules vetoed `read`.
    mutating func cancelRead(_ read: Read, at date: Date) {
        emptyChangeToken = nil
        // Unless something else was read or written meanwhile, remember where this read counted from.
        if synchronizedChangeToken == read.token {
            droppedSyncBaseline = DroppedSync(token: read.token - read.coveredChanges, date: date)
        }
    }

    /// Whether Pasto wrote to the pasteboard at or after `read`: what was read is then either
    /// Pasto's own content or content Pasto has already replaced, and must not be delivered.
    func isReplacedByOwnWrite(_ read: Read) -> Bool {
        guard let writtenChangeToken else { return false }
        return writtenChangeToken >= read.token
    }

    /// Pasto wrote to the pasteboard, which left it at `changeCount`. Polls will not see the
    /// write as a change.
    mutating func didWrite(changeCount: Int) {
        changeToken = changeCount
        synchronizedChangeToken = changeCount
        droppedSyncBaseline = nil
        writtenChangeToken = changeCount
    }
}
