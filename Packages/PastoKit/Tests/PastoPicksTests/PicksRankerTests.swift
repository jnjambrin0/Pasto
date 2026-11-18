import PastoCore
@testable import PastoPicks
import Testing

struct PicksRankerTests {
    // MARK: - Steps and score

    @Test(arguments: [(0, 0), (1, 1), (2, 2), (4, 2), (5, 3), (9, 3), (10, 4), (19, 4), (20, 5), (39, 5)])
    func recencySteps(position: Int, step: Int) {
        #expect(PicksRanker.recencyStep(position) == step)
    }

    @Test(arguments: [(-1, 0), (0, 0), (1, 1), (2, 2), (3, 2), (4, 3), (40, 3)])
    func countSteps(count: Int, step: Int) {
        #expect(PicksRanker.countStep(count) == step)
    }

    @Test func scoreAddsTheFiveTerms() {
        let candidate = features(0, pasteCount: 2, itemClass: .command, pairPasteCount: 4, isSourceOfLatestPaste: true)
        // Position 3 (0.6) + pasted twice (1.5) + pair 4 times (1.5) + latest source (0.8) + suits a terminal (1.0).
        let score = PicksRanker.score(candidate, position: 3, suited: FieldKind.terminal.suitedClasses)
        #expect(abs(score - 5.4) < 1e-9)
    }

    @Test func aMissingPairCountOrLatestSourceAddsNothing() {
        let candidate = features(0, pairPasteCount: nil, isSourceOfLatestPaste: nil)
        #expect(PicksRanker.score(candidate, position: 25, suited: []) == -1.0)
    }

    // MARK: - Nothing to suggest

    @Test func secureInputSuggestsNothing() {
        var generator = SeededGenerator()
        let candidates = (0..<10).map { features($0, pasteCount: 3) }
        #expect(PicksRanker.rank(candidates, fieldKind: .text, isSecureInput: true, using: &generator).isEmpty)
    }

    @Test func aPasswordFieldGetsNothing() {
        var generator = SeededGenerator()
        let candidates = (0..<10).map { features($0, pasteCount: 3) }
        #expect(PicksRanker.rank(candidates, fieldKind: .password, isSecureInput: false, using: &generator).isEmpty)
    }

    @Test func secretsAreNeverSuggested() {
        var generator = SeededGenerator()
        let candidates = [
            features(0, pasteCount: 4, itemClass: .secret),
            features(1, pasteCount: 1),
        ]
        let ranked = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &generator)
        // Without the secret the other one is the newest: 2.0 + 0.8.
        #expect(ranked == [id(1)])
    }

    // MARK: - With a paste history

    @Test func bestFirstAndNewestFirstOnATie() {
        var generator = SeededGenerator()
        let candidates = [
            features(0),                                    // 2.0
            features(1, pasteCount: 1),                     // 1.2 + 0.8 = 2.0
            features(2, pasteCount: 4),                     // 0.6 + 2.2 = 2.8
            features(3, itemClass: .link),                  // 0.6 + 1.0 (url) = 1.6
        ]
        let ranked = PicksRanker.rank(candidates, fieldKind: .url, isSecureInput: false, using: &generator)
        #expect(ranked == [id(2), id(0), id(1), id(3)])
    }

    @Test func atMostFiveAreSuggested() {
        var generator = SeededGenerator()
        let candidates = (0..<12).map { features($0, pasteCount: 4) }
        let ranked = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &generator)
        #expect(ranked == (0..<5).map(id))
    }

    /// The newest candidate scores at least the recency weight of the first position, which is
    /// the threshold: with a paste history there is always something to suggest.
    @Test func theNewestCandidateAlwaysReachesTheThreshold() {
        #expect(PicksMetrics.recencyWeights[0] >= PicksMetrics.minimumBestScore)
        var generator = SeededGenerator()
        // The only pasted item is far back and scores below the threshold by itself.
        let candidates = (0..<30).map { features($0) } + [features(30, pasteCount: 1)]
        #expect(PicksRanker.score(candidates[30], position: 30, suited: []) < PicksMetrics.minimumBestScore)
        let ranked = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &generator)
        #expect(ranked.first == id(0))
    }

    @Test func theThresholdIsInclusive() {
        var generator = SeededGenerator()
        let candidates = [features(0), features(1, pairPasteCount: 1)]
        // The newest scores exactly 2.0.
        let ranked = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &generator)
        #expect(ranked.first == id(0))
    }

    // MARK: - Cold start

    @Test func coldStartSkipsTheFiveNewest() {
        var generator = SeededGenerator()
        let candidates = (0..<8).map { features($0) }
        let ranked = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &generator)
        #expect(Set(ranked) == Set((5..<8).map(id)))
    }

    @Test func coldStartPutsWhatSuitsTheFieldFirst() {
        var generator = SeededGenerator()
        let candidates = (0..<20).map { features($0, itemClass: $0 == 11 || $0 == 17 ? .command : .unclassified) }
        let ranked = PicksRanker.rank(candidates, fieldKind: .terminal, isSecureInput: false, using: &generator)
        #expect(ranked.count == 5)
        #expect(Set(ranked.prefix(2)) == [id(11), id(17)])
        #expect(ranked.allSatisfy { !(0..<5).map(id).contains($0) })
    }

    @Test func coldStartIsRandomAndRepeatableWithTheSameSeed() {
        let candidates = (0..<40).map { features($0) }
        var first = SeededGenerator(seed: 7)
        var second = SeededGenerator(seed: 7)
        var other = SeededGenerator(seed: 8)
        let a = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &first)
        let b = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &second)
        let c = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &other)
        #expect(a == b)
        #expect(a != c)
    }

    @Test func coldStartHasNoThreshold() {
        var generator = SeededGenerator()
        // Far back, every one of them would score below 2.0.
        let candidates = (0..<30).map { features($0) }
        #expect(PicksRanker.rank(candidates, fieldKind: .text, isSecureInput: false, using: &generator).count == 5)
    }

    @Test func aLatestSourceAloneCountsAsHistory() {
        var generator = SeededGenerator()
        let candidates = (0..<8).map { features($0, isSourceOfLatestPaste: $0 == 7) }
        let ranked = PicksRanker.rank(candidates, fieldKind: nil, isSecureInput: false, using: &generator)
        // Not a cold start: the newest five are not skipped.
        #expect(ranked.first == id(0))
    }

    // MARK: -

    private func id(_ index: Int) -> ItemID {
        ItemID(rawValue: "item-\(index)")
    }

    private func features(
        _ rank: Int,
        pasteCount: Int = 0,
        itemClass: ItemClass = .unclassified,
        pairPasteCount: Int? = 0,
        isSourceOfLatestPaste: Bool? = nil
    ) -> CandidateFeatures {
        CandidateFeatures(
            itemIdentifier: id(rank),
            recencyRank: rank,
            pasteCount: pasteCount,
            sourceAppBundleIdentifier: nil,
            itemType: .text,
            itemClass: itemClass,
            pairPasteCount: pairPasteCount,
            isSourceOfLatestPaste: isSourceOfLatestPaste
        )
    }
}
