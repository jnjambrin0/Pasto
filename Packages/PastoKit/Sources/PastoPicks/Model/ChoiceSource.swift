/// Where a pasted item was chosen.
public enum ChoiceSource: String, Sendable, Codable {
    /// The suggestions in the strip.
    case strip
    /// The clipboard history or a pinboard.
    case list
    /// Search results.
    case search
}
