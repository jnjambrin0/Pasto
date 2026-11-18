/// Identifies a clipboard item across the app (the stored `identifier`, a UUID string).
///
/// `RawRepresentable` so it encodes as the bare string.
public struct ItemID: RawRepresentable, Hashable, Sendable, Codable {
    public let rawValue: String

    public init(rawValue: String) {
        self.rawValue = rawValue
    }
}
