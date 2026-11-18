import Foundation

/// What a page's markup says about itself, as far as link previews read it: its title and its
/// `<meta>`, `<link>` and `<base>` up to `</head>`, decoded with the page's character encoding
/// and character references.
struct HTMLHead: Equatable {
    struct Meta: Equatable {
        /// `property`, `name` and `itemprop`, trimmed and in lower case.
        var property: String?
        var name: String?
        var itemprop: String?
        /// As written, references decoded.
        var content: String

        /// Whether the tag is `key`, by `property` or by `name`: pages use either for Open Graph
        /// and Twitter keys, and Link Presentation reads both.
        func isNamed(_ key: String) -> Bool {
            property == key || name == key
        }
    }

    struct Link: Equatable {
        /// Trimmed and in lower case.
        var rel: String
        var href: String
        var sizes: String?
        var type: String?
        /// Whether a browser's parser puts it in the head (`HTMLHeadScanner`).
        var isInHead = true
    }

    /// The text of the first `<title>`, references decoded and white space as written.
    var title: String?
    var metas: [Meta] = []
    var links: [Link] = []
    /// The first `<base href>`.
    var baseHref: String?

    init(title: String? = nil, metas: [Meta] = [], links: [Link] = [], baseHref: String? = nil) {
        self.title = title
        self.metas = metas
        self.links = links
        self.baseHref = baseHref
    }

    /// Reads `data`, the start of a page. The encoding is, in this order, the one a byte order
    /// mark gives, `charset` (from the response's `Content-Type`), the page's
    /// `<meta charset>`, or else detected (`HTMLTextEncoding.detected(in:)`).
    init(parsing data: Data, charset: String?) {
        var bytes = [UInt8](data)
        let markedEncoding = Self.removeByteOrderMark(from: &bytes)
        var scanner = HTMLHeadScanner()
        bytes.withUnsafeBytes { scanner.scan($0, isComplete: true) }

        let used = Self.usedRanges(of: scanner)
        let encoding = markedEncoding
            ?? charset.flatMap(HTMLTextEncoding.init(label:))
            ?? Self.declaredCharset(in: scanner.elements, bytes: bytes).flatMap(HTMLTextEncoding.init(label:))
            ?? HTMLTextEncoding.detected(in: used.map { bytes[$0] })

        func text(_ range: Range<Int>?) -> String? {
            range.map { HTMLCharacterReferences.decode(encoding.decode(bytes[$0]), inAttribute: true) }
        }
        func key(_ range: Range<Int>?) -> String? {
            text(range).map { $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() }
        }

        title = scanner.title.map { HTMLCharacterReferences.decode(encoding.decode(bytes[$0]), inAttribute: false) }
        for element in scanner.elements {
            switch element.name {
            case "meta":
                guard let content = text(element.value(of: "content")) else { continue }
                let meta = Meta(
                    property: key(element.value(of: "property")),
                    name: key(element.value(of: "name")),
                    itemprop: key(element.value(of: "itemprop")),
                    content: content
                )
                if meta.property != nil || meta.name != nil || meta.itemprop != nil {
                    metas.append(meta)
                }
            case "link":
                guard let rel = key(element.value(of: "rel")), let href = text(element.value(of: "href")) else { continue }
                links.append(Link(
                    rel: rel, href: href, sizes: key(element.value(of: "sizes")), type: key(element.value(of: "type")),
                    isInHead: element.isInHead
                ))
            case "base":
                if baseHref == nil, let href = text(element.value(of: "href")) {
                    baseHref = href
                }
            default:
                continue
            }
        }
    }

    /// Takes a byte order mark off `bytes` and returns the encoding it marks. A UTF-16 page is
    /// turned into UTF-8 here, so that its markup can be read byte by byte.
    private static func removeByteOrderMark(from bytes: inout [UInt8]) -> HTMLTextEncoding? {
        if bytes.starts(with: [0xEF, 0xBB, 0xBF]) {
            bytes.removeFirst(3)
            return .utf8
        }
        let isLittleEndian = bytes.starts(with: [0xFF, 0xFE])
        guard isLittleEndian || bytes.starts(with: [0xFE, 0xFF]) else { return nil }
        // A page cut at the byte limit can end in half a code unit; it is left out.
        let units = stride(from: 2, to: bytes.count - 1, by: 2).map { index in
            isLittleEndian
                ? UInt16(bytes[index]) | UInt16(bytes[index + 1]) << 8
                : UInt16(bytes[index]) << 8 | UInt16(bytes[index + 1])
        }
        bytes = Array(String(decoding: units, as: UTF16.self).utf8)
        return .utf8
    }

    /// The parts of the page that are read: the title and the values of the attributes used.
    private static func usedRanges(of scanner: HTMLHeadScanner) -> [Range<Int>] {
        let attributes: Set<String> = ["content", "property", "name", "itemprop", "rel", "href", "sizes", "type"]
        var ranges = scanner.title.map { [$0] } ?? []
        for element in scanner.elements {
            ranges += element.attributes.filter { attributes.contains($0.name) }.map(\.value)
        }
        return ranges
    }

    /// The first encoding the page declares: `<meta charset>` or
    /// `<meta http-equiv="Content-Type" content="…; charset=…">`.
    private static func declaredCharset(in elements: [HTMLHeadScanner.Element], bytes: [UInt8]) -> String? {
        func ascii(_ range: Range<Int>) -> String {
            String(decoding: bytes[range], as: UTF8.self)
        }
        for element in elements where element.name == "meta" {
            if let charset = element.value(of: "charset") {
                return ascii(charset)
            }
            if let equivalent = element.value(of: "http-equiv"),
               ascii(equivalent).trimmingCharacters(in: .whitespaces).lowercased() == "content-type",
               let content = element.value(of: "content"),
               let charset = Self.charset(inContentType: ascii(content)) {
                return charset
            }
        }
        return nil
    }

    /// The `charset` parameter of a `Content-Type` value.
    static func charset(inContentType value: String) -> String? {
        let lowered = value.lowercased()
        guard let range = lowered.range(of: "charset") else { return nil }
        var rest = lowered[range.upperBound...].drop { $0 == " " }
        guard rest.first == "=" else { return nil }
        rest = rest.dropFirst().drop { $0 == " " || $0 == "\"" || $0 == "'" }
        let label = rest.prefix { !";,\"' ".contains($0) }
        return label.isEmpty ? nil : String(label)
    }
}
