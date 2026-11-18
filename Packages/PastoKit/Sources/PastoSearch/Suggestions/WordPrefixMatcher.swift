import Foundation

/// Matches what the user typed against the name of a suggestion: every typed word has to start a
/// word of the name, in the same order, whatever the case and the diacritics. `la 30` matches
/// `Last 30 days`.
public enum WordPrefixMatcher {
    /// - Returns: The part of `candidate` each typed word matched, for highlighting; `nil` when
    ///   some word matched nothing or nothing was typed.
    public static func matchedRanges(of typed: String, in candidate: String) -> [Range<String.Index>]? {
        let words = typed.split(separator: " ")
        guard !words.isEmpty else { return nil }

        var ranges: [Range<String.Index>] = []
        var searchStart = candidate.startIndex
        for word in words {
            guard let range = firstRange(of: word, startingAWordIn: candidate, from: searchStart) else { return nil }
            ranges.append(range)
            searchStart = range.upperBound
        }
        return ranges
    }

    private static func firstRange(
        of word: Substring,
        startingAWordIn candidate: String,
        from start: String.Index
    ) -> Range<String.Index>? {
        guard let first = word.first else { return nil }
        var searchStart = start
        while let range = candidate.range(
            of: word, options: [.caseInsensitive, .diacriticInsensitive], range: searchStart..<candidate.endIndex
        ) {
            // A word boundary: the match and what precedes it are of different kinds.
            let precedingIsWordCharacter = range.lowerBound > candidate.startIndex
                && isWordCharacter(candidate[candidate.index(before: range.lowerBound)])
            if precedingIsWordCharacter != isWordCharacter(first) {
                return range
            }
            searchStart = candidate.index(after: range.lowerBound)
        }
        return nil
    }

    private static func isWordCharacter(_ character: Character) -> Bool {
        character.isLetter || character.isNumber || character == "_"
    }
}
