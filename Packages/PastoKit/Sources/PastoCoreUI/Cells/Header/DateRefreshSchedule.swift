import Foundation

/// When a card's date label works its text out again (`DateLabel`): every 30 s from the last time.
enum DateRefreshSchedule {
    static let interval: TimeInterval = 30

    /// What a label paused while its window was hidden does when it shows again, so that it reads
    /// exactly what it would have read had it refreshed every `interval` all along: the text of
    /// the last refresh it missed, if it missed any, and when the next one is due.
    ///
    /// - Parameters:
    ///   - due: When the label was next due to refresh as it was paused.
    /// - Returns: `textDate`, the moment to work the text out for (`nil` when no refresh was
    ///   missed and the text stands); `nextDue`, when to refresh next.
    static func resume(due: Date, now: Date) -> (textDate: Date?, nextDue: Date) {
        guard now >= due else { return (nil, due) }
        let missed = (now.timeIntervalSince(due) / interval).rounded(.down)
        let last = due.addingTimeInterval(missed * interval)
        return (last, last.addingTimeInterval(interval))
    }
}
