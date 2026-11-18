import Foundation

/// When a copied string is a colour.
enum HexColor {
    /// Six hexadecimal digits with an optional `#`, and nothing else. The string is not trimmed.
    private static let pattern = "^#?[A-Fa-f0-9]{6}$"
    /// UTF-8 bytes of the longest string the pattern can match, with room to spare.
    static let maximumLength = 16

    /// The colour as `0xRRGGBB`, or `nil` if `string` is not one.
    ///
    /// Besides matching the pattern, the string must start with `#` or contain a hexadecimal
    /// letter: six plain digits are far more often a number than a colour.
    static func code(of string: String) -> UInt64? {
        // Nothing longer can match: seven characters and, since `$` also matches before a final
        // line break, one of those (at most three bytes). Spares a long copy the pattern.
        guard string.utf8.count <= maximumLength,
              string.range(of: pattern, options: .regularExpression) != nil,
              // Past the pattern, any letter is one of A–F.
              string.hasPrefix("#") || string.contains(where: \.isLetter)
        else { return nil }
        return UInt64(string.filter(\.isHexDigit), radix: 16)
    }
}
