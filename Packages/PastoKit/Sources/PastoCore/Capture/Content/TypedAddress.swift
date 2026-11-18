/// A quick look at the start of a long string before it is tried as an address.
///
/// Trying a string as an address percent-encodes it and parses the result, which for a copy of
/// hundreds of megabytes means two more copies of it. An address with a scheme and a host — the
/// only kind capture keeps — has to start with `scheme://`, and percent-encoding leaves those
/// characters alone; a long string that does not start that way cannot be one, and is not tried.
enum TypedAddress {
    /// Strings up to this many UTF-8 bytes always take the full test, whatever they start with.
    static let quickRejectLength = 2048

    /// `false` only when `string` certainly has no scheme and host once percent-encoded.
    static func mayHaveSchemeAndHost(_ string: String) -> Bool {
        let bytes = string.utf8
        guard bytes.count > quickRejectLength else { return true }
        return startsWithSchemeAndAuthority(bytes)
    }

    /// Whether the bytes start with `ALPHA *( ALPHA / DIGIT / "+" / "-" / "." ) "://"`
    /// (RFC 3986, sections 3.1 and 3.2).
    static func startsWithSchemeAndAuthority(_ bytes: some Collection<UInt8>) -> Bool {
        var index = bytes.startIndex
        guard index != bytes.endIndex, isLetter(bytes[index]) else { return false }
        index = bytes.index(after: index)
        while index != bytes.endIndex, isSchemeCharacter(bytes[index]) {
            index = bytes.index(after: index)
        }
        for expected in [UInt8(ascii: ":"), UInt8(ascii: "/"), UInt8(ascii: "/")] {
            guard index != bytes.endIndex, bytes[index] == expected else { return false }
            index = bytes.index(after: index)
        }
        return true
    }

    private static func isLetter(_ byte: UInt8) -> Bool {
        (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(byte) || (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(byte)
    }

    private static func isSchemeCharacter(_ byte: UInt8) -> Bool {
        isLetter(byte) || (UInt8(ascii: "0")...UInt8(ascii: "9")).contains(byte)
            || byte == UInt8(ascii: "+") || byte == UInt8(ascii: "-") || byte == UInt8(ascii: ".")
    }
}
