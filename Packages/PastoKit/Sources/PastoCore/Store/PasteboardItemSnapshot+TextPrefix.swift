import Foundation

extension PasteboardItemSnapshot {
    /// The start of the item's string (`plainText`), for whoever only keeps the beginning of it.
    ///
    /// Which representation is the item's string is decided as `plainText` decides it — the
    /// first whose bytes are all valid UTF-8 — but by checking the bytes where they are, and only
    /// the start of that representation is decoded. A text of hundreds of megabytes costs a pass
    /// over its bytes instead of a string as large as itself.
    ///
    /// - Returns: The string itself (`isWhole`) or, when it is longer, a start of it with more than
    ///   `characters` characters, whose first `characters` are the string's own first ones.
    func plainTextPrefix(characters: Int) -> (text: String, isWhole: Bool)? {
        for type in Self.stringTypes {
            guard let data = dataByType[type], Self.isValidUTF8(data) else { continue }
            return Self.prefix(ofValidUTF8: data, characters: characters)
        }
        return nil
    }

    /// Whether `String(data:encoding: .utf8)` would decode `data`.
    static func isValidUTF8(_ data: Data) -> Bool {
        data.withUnsafeBytes { raw in
            (try? UTF8Span(validating: raw.assumingMemoryBound(to: UInt8.self).span)) != nil
        }
    }

    private static let byteOrderMark: [UInt8] = [0xEF, 0xBB, 0xBF]

    /// The first characters of valid UTF-8 as `String(data:encoding: .utf8)` decodes it, which
    /// drops a leading byte-order mark.
    private static func prefix(ofValidUTF8 data: Data, characters: Int) -> (text: String, isWhole: Bool) {
        data.withUnsafeBytes { raw in
            let bytes = raw.starts(with: byteOrderMark) ? UnsafeRawBufferPointer(rebasing: raw.dropFirst(byteOrderMark.count)) : raw
            // A few bytes per character is usually enough; more is decoded only when it is not.
            var length = min(bytes.count, (characters + 1) * 4 + 64)
            while true {
                guard length < bytes.count else {
                    return (String(decoding: bytes, as: UTF8.self), true)
                }
                // Cut where a character's scalar begins, never inside one.
                var end = length
                while end > 0, bytes[end] & 0xC0 == 0x80 {
                    end -= 1
                }
                // Every character boundary before the end of the start is one of the whole
                // string's: a boundary depends on what precedes it and on the scalar after it.
                let start = String(decoding: UnsafeRawBufferPointer(rebasing: bytes[0..<end]), as: UTF8.self)
                if start.count > characters {
                    return (start, false)
                }
                length = min(bytes.count, length * 2)
            }
        }
    }
}
