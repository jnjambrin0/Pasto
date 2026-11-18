import Foundation

/// Tells a link from text that merely contains or starts with one.
enum LinkDetector {
    /// Whether an item that could be a link is one: its string, once trimmed, must be a single
    /// link from the first character to the last.
    ///
    /// Everything that keeps the test from running — no string, an empty one, no detector, no
    /// link found — leaves the item a link.
    static func isWholeLink(_ string: String?) -> Bool {
        guard let string else { return true }
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        else { return true }

        let whole = NSRange(location: 0, length: (trimmed as NSString).length)
        guard let match = detector.firstMatch(in: trimmed, options: [], range: whole) else { return true }
        return match.range == whole
    }
}
