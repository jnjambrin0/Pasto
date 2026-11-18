import PastoCore

/// The recent pastes the ranking learns from, newest first. Counting is all the learning there is.
struct PasteHistory: Sendable {
    /// Newest first.
    let events: [PasteEvent]

    init(newestFirst events: [PasteEvent]) {
        self.events = events
    }

    /// The window of the journal the ranking looks at: its last `window` lines, which are the
    /// newest because the journal only grows at the end.
    init(journal: [PasteEvent], window: Int = PicksMetrics.journalWindow) {
        events = journal.suffix(window).reversed()
    }

    /// How often `item` was pasted.
    func pasteCount(of item: ItemID) -> Int {
        events.count { $0.itemIdentifier == item }
    }

    /// How often something copied in `source` was pasted into `destination`.
    func pasteCount(from source: String, into destination: String) -> Int {
        events.count { $0.sourceAppBundleIdentifier == source && $0.destinationAppBundleIdentifier == destination }
    }

    /// The last paste into `destination`, if there was one.
    func latestPaste(into destination: String) -> PasteEvent? {
        events.first { $0.destinationAppBundleIdentifier == destination }
    }
}
