import Foundation

/// A regular expression the rules test texts against.
struct TextPattern: Sendable {
    enum Scope {
        /// The pattern has to match the text from its first character to its last.
        case wholeText
        /// The pattern may match anywhere in the text.
        case anywhere
    }

    private let expression: NSRegularExpression

    /// - Parameter pattern: A valid ICU pattern, a literal of this module.
    init(_ pattern: String, scope: Scope, options: NSRegularExpression.Options = []) {
        let anchored = scope == .wholeText ? "^(?:\(pattern))$" : pattern
        // The patterns are literals: an invalid one is a programming error.
        expression = try! NSRegularExpression(pattern: anchored, options: options)
    }

    func matches(_ text: String) -> Bool {
        expression.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) != nil
    }
}
