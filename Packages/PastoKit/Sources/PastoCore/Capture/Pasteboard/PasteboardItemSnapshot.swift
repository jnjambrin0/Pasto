import Foundation

/// An immutable copy of one pasteboard item: every representation it offered, in the order the
/// source application declared them.
public struct PasteboardItemSnapshot: Hashable, Sendable, Codable {
    /// Uniform type identifiers, in declaration order (the first is the richest).
    public var types: [String]
    public var dataByType: [String: Data]

    public init(types: [String], dataByType: [String: Data]) {
        self.types = types
        self.dataByType = dataByType
    }

    /// The item's string: its first representation, in this order, whose bytes are valid UTF-8.
    /// Type detection, the checksum and plain-text paste all read an item through it.
    public var plainText: String? {
        for type in Self.stringTypes {
            if let data = dataByType[type], let string = String(data: data, encoding: .utf8) {
                return string
            }
        }
        return nil
    }

    static let stringTypes = [
        PasteboardType.plainText,
        PasteboardType.utf8PlainText,
        PasteboardType.text,
        PasteboardType.url,
    ]
}
