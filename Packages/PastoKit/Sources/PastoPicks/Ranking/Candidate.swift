import PastoCore

/// A history item that may be suggested, with its class already worked out.
struct Candidate: Sendable, Hashable {
    var id: ItemID
    var type: ItemType
    var sourceAppBundleIdentifier: String?
    var itemClass: ItemClass
}

extension CandidateFeatures {
    /// The features of `candidates`, which are the newest history items, newest first, for a
    /// paste into `destination`.
    static func features(
        of candidates: [Candidate],
        history: PasteHistory,
        destination: String
    ) -> [CandidateFeatures] {
        let latestSource = history.latestPaste(into: destination)?.sourceAppBundleIdentifier
        return candidates.enumerated().map { rank, candidate in
            let source = candidate.sourceAppBundleIdentifier
            return CandidateFeatures(
                itemIdentifier: candidate.id,
                recencyRank: rank,
                pasteCount: history.pasteCount(of: candidate.id),
                sourceAppBundleIdentifier: source,
                itemType: candidate.type,
                itemClass: candidate.itemClass,
                // Both are filled in for every candidate: 0 and false when the item came from no
                // known application or nothing was pasted into the destination yet.
                pairPasteCount: source.map { history.pasteCount(from: $0, into: destination) } ?? 0,
                isSourceOfLatestPaste: source != nil && latestSource == source
            )
        }
    }
}
