import Foundation

/// Every number suggestions work with.
enum PicksMetrics {
    // MARK: Ranking

    /// How many of the newest history items are considered.
    static let candidateLimit = 40
    /// How many of the newest paste events the ranking learns from.
    static let journalWindow = 500
    /// How many suggestions are shown at most.
    static let maximumSuggestions = 5
    /// With a paste history, nothing is suggested unless the best score reaches this.
    static let minimumBestScore = 2.0

    /// By position among the candidates, newest first: 0, 1, 2–4, 5–9, 10–19, 20 and beyond.
    static let recencyWeights = [2.0, 1.2, 0.6, 0.0, -0.5, -1.0]
    /// By how often the item was pasted: never, once, 2–3 times, 4 times or more.
    static let pasteCountWeights = [0.0, 0.8, 1.5, 2.2]
    /// By how often something from the item's application was pasted into the destination,
    /// in the same steps as `pasteCountWeights`.
    static let pairPasteCountWeights = [0.0, 0.5, 1.0, 1.5]
    /// The item comes from the application the last paste into the destination came from.
    static let latestSourceBonus = 0.8
    /// The item's class is one the destination field takes.
    static let fieldMatchBonus = 1.0

    // MARK: Journals

    /// Paste events older than this are dropped whenever one is added.
    static let pasteJournalRetention: TimeInterval = 90 * 24 * 60 * 60
    /// Pick log entries older than this are dropped whenever one is added.
    static let pickLogRetention: TimeInterval = 30 * 24 * 60 * 60
    /// The class store keeps this many records, the newest ones.
    static let classStoreCapacity = 5000

    // MARK: Classification

    /// Longer texts are left unclassified by the rules.
    static let ruleTextLimit = 4096
    /// Only this much of a text is searched for secrets.
    static let secretScanLimit = 16384
    /// Texts the language model is asked about: neither shorter nor longer than this.
    static let modelTextLengths = 12...2000
    /// How much of a text the language model is shown.
    static let modelPromptLimit = 1500
    /// How long a text waits after being copied before the model is asked about it.
    static let classificationDebounce: Duration = .seconds(2)

    // MARK: Language model

    static let classificationTimeout: Duration = .seconds(5)
    static let fieldKindTimeout: Duration = .seconds(10)
    /// Both questions are answered with a single word.
    static let maximumResponseTokens = 16

    // MARK: Screen context

    static let windowLookupTimeout: Duration = .seconds(5)
    static let captureTimeout: Duration = .seconds(5)
    /// The screenshot's longer side is scaled down to this many pixels if it exceeds it.
    static let maximumCaptureSide: CGFloat = 16384
}
