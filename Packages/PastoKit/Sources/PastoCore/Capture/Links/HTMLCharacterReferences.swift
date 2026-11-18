/// Decodes the character references of a page's text and attribute values (`&amp;`, `&#233;`,
/// `&#x1F600;`) the way a browser does for the few parts link previews read: the title and the
/// `content` and `href` of `<meta>` and `<link>`.
///
/// Named references cover HTML 4 plus `&apos;` (`HTMLCharacterReferences+Names.swift`): what
/// pages put in titles. An unknown name stays as it is, as in a browser.
enum HTMLCharacterReferences {
    /// `text` with its references replaced. In an attribute value a name without its semicolon
    /// followed by a letter, a digit or `=` is not a reference (it is part of a query string, as
    /// in `?a=1&copy=2`), as HTML specifies.
    static func decode(_ text: String, inAttribute: Bool) -> String {
        guard text.utf8.contains(ampersand) else { return text }
        let bytes = Array(text.utf8)
        var output = ""
        output.reserveCapacity(bytes.count)
        var copiedUpTo = 0
        var index = 0
        while index < bytes.count {
            guard bytes[index] == ampersand,
                  let (replacement, end) = reference(in: bytes, at: index, inAttribute: inAttribute)
            else {
                index += 1
                continue
            }
            // Cuts fall on `&` and after a reference's last ASCII byte, so each piece is whole UTF-8.
            output += String(decoding: bytes[copiedUpTo..<index], as: UTF8.self)
            output += replacement
            index = end
            copiedUpTo = end
        }
        output += String(decoding: bytes[copiedUpTo...], as: UTF8.self)
        return output
    }

    private static let ampersand = UInt8(ascii: "&")
    private static let semicolon = UInt8(ascii: ";")

    /// The reference that starts at the `&` at `start`: its text and the index after it.
    private static func reference(in bytes: [UInt8], at start: Int, inAttribute: Bool) -> (String, Int)? {
        let first = start + 1
        guard first < bytes.count else { return nil }
        if bytes[first] == UInt8(ascii: "#") {
            return numericReference(in: bytes, at: first + 1)
        }
        var end = first
        while end < bytes.count, end - first < longestName, isAlphanumeric(bytes[end]) {
            end += 1
        }
        guard end > first else { return nil }
        if end < bytes.count, bytes[end] == semicolon,
           let value = names[String(decoding: bytes[first..<end], as: UTF8.self)] {
            return (value, end + 1)
        }
        // Without a semicolon, only the names HTML kept for old pages, longest first: `&notit;` is `¬it;`.
        for length in stride(from: min(end - first, longestLegacyName), through: 2, by: -1) {
            let name = String(decoding: bytes[first..<first + length], as: UTF8.self)
            guard legacyNames.contains(name), let value = names[name] else { continue }
            let next = first + length
            if inAttribute, next < bytes.count, isAlphanumeric(bytes[next]) || bytes[next] == UInt8(ascii: "=") {
                return nil
            }
            return (value, next)
        }
        return nil
    }

    /// `&#…;` from its first digit (or `x`): the character, or U+FFFD for one HTML does not allow.
    private static func numericReference(in bytes: [UInt8], at start: Int) -> (String, Int)? {
        var index = start
        var radix: UInt32 = 10
        if index < bytes.count, bytes[index] | 0x20 == UInt8(ascii: "x") {
            radix = 16
            index += 1
        }
        let digitsStart = index
        var value: UInt32 = 0
        while index < bytes.count, let digit = digitValue(bytes[index], radix: radix) {
            // Past the last code point the value only needs to stay out of range.
            value = min(value * radix + digit, 0x110000)
            index += 1
        }
        guard index > digitsStart else { return nil }
        if index < bytes.count, bytes[index] == semicolon {
            index += 1
        }
        return (String(character(for: value)), index)
    }

    private static func character(for value: UInt32) -> Character {
        // References to C1 controls mean what those bytes are in windows-1252: `&#150;` is "–".
        if let scalar = HTMLTextEncoding.windows1252Scalar(for: value) {
            return Character(scalar)
        }
        guard value != 0, let scalar = Unicode.Scalar(value) else { return "\u{FFFD}" }
        return Character(scalar)
    }

    private static func digitValue(_ byte: UInt8, radix: UInt32) -> UInt32? {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): return UInt32(byte - UInt8(ascii: "0"))
        case UInt8(ascii: "a")...UInt8(ascii: "f") where radix == 16: return UInt32(byte - UInt8(ascii: "a") + 10)
        case UInt8(ascii: "A")...UInt8(ascii: "F") where radix == 16: return UInt32(byte - UInt8(ascii: "A") + 10)
        default: return nil
        }
    }

    private static func isAlphanumeric(_ byte: UInt8) -> Bool {
        switch byte {
        case UInt8(ascii: "0")...UInt8(ascii: "9"), UInt8(ascii: "a")...UInt8(ascii: "z"), UInt8(ascii: "A")...UInt8(ascii: "Z"): true
        default: false
        }
    }

    private static let longestName = names.keys.map(\.utf8.count).max() ?? 0
    private static let longestLegacyName = legacyNames.map(\.utf8.count).max() ?? 0
}
