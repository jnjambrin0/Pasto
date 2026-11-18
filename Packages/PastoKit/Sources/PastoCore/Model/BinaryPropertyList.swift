import Foundation

/// The encoding of every structured blob in the store (`rawPreview`, `rawPasteboardItems`, `rawAttributes`).
enum BinaryPropertyList {
    static func encode(_ value: some Encodable) throws -> Data {
        let encoder = PropertyListEncoder()
        encoder.outputFormat = .binary
        return try encoder.encode(value)
    }

    static func decode<Value: Decodable>(_ type: Value.Type, from data: Data) throws -> Value {
        try PropertyListDecoder().decode(type, from: data)
    }
}
