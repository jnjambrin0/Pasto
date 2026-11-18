import PastoCore

/// Chooses what to suggest: a fixed weighted sum over a few counts, with a random pick while
/// there is nothing to learn from.
enum PicksRanker {
    typealias Metrics = PicksMetrics

    /// The items to suggest, best first; at most `PicksMetrics.maximumSuggestions`.
    ///
    /// - Parameters:
    ///   - candidates: The candidates' features.
    ///   - fieldKind: The destination field, when known.
    ///   - isSecureInput: A password field has the keyboard.
    ///   - generator: The randomness of the cold start.
    static func rank(
        _ candidates: [CandidateFeatures],
        fieldKind: FieldKind?,
        isSecureInput: Bool,
        using generator: inout some RandomNumberGenerator
    ) -> [ItemID] {
        guard !isSecureInput, fieldKind != .password else { return [] }
        let suited = fieldKind?.suitedClasses ?? []
        let byRecency = candidates
            .filter { $0.itemClass != .secret }
            .sorted { $0.recencyRank < $1.recencyRank }

        guard byRecency.contains(where: hasPasteHistory) else {
            return coldStart(byRecency, suited: suited, using: &generator)
        }
        let scored = byRecency.enumerated().map { position, candidate in
            (candidate, score(candidate, position: position, suited: suited))
        }
        let best = scored.sorted { lhs, rhs in
            lhs.1 != rhs.1 ? lhs.1 > rhs.1 : lhs.0.recencyRank < rhs.0.recencyRank
        }
        guard let top = best.first, top.1 >= Metrics.minimumBestScore else { return [] }
        return best.prefix(Metrics.maximumSuggestions).map(\.0.itemIdentifier)
    }

    /// The sum of the five terms for the candidate in `position` among the candidates, newest first.
    static func score(_ candidate: CandidateFeatures, position: Int, suited: Set<ItemClass>) -> Double {
        Metrics.recencyWeights[recencyStep(position)]
            + Metrics.pasteCountWeights[countStep(candidate.pasteCount)]
            + Metrics.pairPasteCountWeights[countStep(candidate.pairPasteCount ?? 0)]
            + (candidate.isSourceOfLatestPaste == true ? Metrics.latestSourceBonus : 0)
            + (suited.contains(candidate.itemClass) ? Metrics.fieldMatchBonus : 0)
    }

    /// 0, 1, 2–4, 5–9, 10–19, 20 and beyond.
    static func recencyStep(_ position: Int) -> Int {
        switch position {
        case ...0: 0
        case 1: 1
        case 2...4: 2
        case 5...9: 3
        case 10...19: 4
        default: 5
        }
    }

    /// None, one, 2–3, 4 or more.
    static func countStep(_ count: Int) -> Int {
        switch count {
        case ...0: 0
        case 1: 1
        case 2...3: 2
        default: 3
        }
    }

    private static func hasPasteHistory(_ candidate: CandidateFeatures) -> Bool {
        candidate.pasteCount > 0 || (candidate.pairPasteCount ?? 0) > 0 || candidate.isSourceOfLatestPaste == true
    }

    /// Nothing has been learnt yet: skip what the panel already shows first, shuffle the rest
    /// and put what suits the field in front. No threshold applies.
    private static func coldStart(
        _ byRecency: [CandidateFeatures],
        suited: Set<ItemClass>,
        using generator: inout some RandomNumberGenerator
    ) -> [ItemID] {
        let shuffled = byRecency.dropFirst(Metrics.maximumSuggestions).shuffled(using: &generator)
        let fitting = shuffled.filter { suited.contains($0.itemClass) }
        let others = shuffled.filter { !suited.contains($0.itemClass) }
        return (fitting + others).prefix(Metrics.maximumSuggestions).map(\.itemIdentifier)
    }
}
