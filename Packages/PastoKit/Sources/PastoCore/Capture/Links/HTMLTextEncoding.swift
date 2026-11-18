import CoreFoundation
import Foundation

/// The character encoding of a page's text, picked and applied as a browser does.
struct HTMLTextEncoding: Equatable, Sendable {
    let encoding: String.Encoding

    static let utf8 = HTMLTextEncoding(encoding: .utf8)
    static let windows1252 = HTMLTextEncoding(encoding: .windowsCP1252)

    private init(encoding: String.Encoding) {
        self.encoding = encoding
    }

    /// The encoding a `charset` label names, read the way HTML reads labels; `nil` for a label
    /// the system does not know.
    init?(label: String) {
        let label = label.trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(["\"", "'"])).lowercased()
        switch label {
        case "utf-8", "utf8", "unicode-1-1-utf-8":
            self = .utf8
        // HTML reads Latin-1 and ASCII labels as windows-1252, which they are a part of.
        case "iso-8859-1", "iso8859-1", "iso_8859-1", "latin1", "l1", "cp819", "ibm819", "csisolatin1",
             "us-ascii", "ascii", "ansi_x3.4-1968", "windows-1252", "cp1252", "x-cp1252":
            self = .windows1252
        // A page whose markup was found by reading it byte by byte is not UTF-16, whatever it says.
        case "utf-16", "utf-16le", "utf-16be":
            self = .utf8
        default:
            let encoding = CFStringConvertIANACharSetNameToEncoding(label as CFString)
            guard encoding != kCFStringEncodingInvalidId else { return nil }
            self.init(encoding: String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(encoding)))
        }
    }

    /// The encoding of a page that does not declare one: UTF-8 when `pieces` — the parts of the
    /// page that will be read — are valid UTF-8, and windows-1252 otherwise, the browsers'
    /// default for pages in Western languages. Browsers would read undeclared UTF-8 as
    /// windows-1252 too, and show "CafÃ©"; reading it right costs nothing.
    static func detected(in pieces: [ArraySlice<UInt8>]) -> HTMLTextEncoding {
        pieces.allSatisfy { String(validating: $0, as: UTF8.self) != nil } ? .utf8 : .windows1252
    }

    /// `bytes` as text. Never fails: bytes the encoding cannot read become U+FFFD, or for
    /// windows-1252 the character HTML gives them.
    func decode(_ bytes: ArraySlice<UInt8>) -> String {
        if encoding == .utf8 {
            return String(decoding: bytes, as: UTF8.self)
        }
        if let text = String(bytes: bytes, encoding: encoding) {
            return text
        }
        if encoding == .windowsCP1252 {
            // The five bytes windows-1252 leaves undefined stand for the C1 control of the same value.
            var text = String.UnicodeScalarView()
            for byte in bytes {
                text.append(Self.windows1252Scalar(for: UInt32(byte)) ?? Unicode.Scalar(byte))
            }
            return String(text)
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    /// What windows-1252 has where Latin-1 has C1 controls (0x80–0x9F); `nil` elsewhere and for
    /// the five values it leaves undefined. HTML also reads character references to those
    /// values this way.
    static func windows1252Scalar(for value: UInt32) -> Unicode.Scalar? {
        windows1252Controls[value].flatMap(Unicode.Scalar.init)
    }

    private static let windows1252Controls: [UInt32: UInt32] = [
        0x80: 0x20AC, 0x82: 0x201A, 0x83: 0x0192, 0x84: 0x201E, 0x85: 0x2026, 0x86: 0x2020, 0x87: 0x2021,
        0x88: 0x02C6, 0x89: 0x2030, 0x8A: 0x0160, 0x8B: 0x2039, 0x8C: 0x0152, 0x8E: 0x017D, 0x91: 0x2018,
        0x92: 0x2019, 0x93: 0x201C, 0x94: 0x201D, 0x95: 0x2022, 0x96: 0x2013, 0x97: 0x2014, 0x98: 0x02DC,
        0x99: 0x2122, 0x9A: 0x0161, 0x9B: 0x203A, 0x9C: 0x0153, 0x9E: 0x017E, 0x9F: 0x0178,
    ]
}
