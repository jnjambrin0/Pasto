/// Identifies the clipboard history or a pinboard (the stored `identifier`).
///
/// `RawRepresentable` so it encodes as the bare string.
public struct ListID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }

    /// The clipboard history: the one list every store has, under a fixed identifier.
    public static let clipboard = ListID(rawValue: "clipboard")
}
