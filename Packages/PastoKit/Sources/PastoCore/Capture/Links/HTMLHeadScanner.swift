import Darwin

/// Reads a page's markup as far as link previews need it: every `<meta>`, `<link>` and
/// `<base>` up to `</head>`, and the first `<title>` wherever it is — a page can have an empty
/// head and its title in the body (info.cern.ch), and a browser finds it there. When the head
/// gives no title of any kind, reading goes on after `</head>` until one turns up. Comments,
/// scripts and styles are skipped
/// whole, and malformed markup is read the way a browser's parser reads it: unquoted and
/// repeated attributes, upper case, a `<` that opens nothing, a title that never closes.
///
/// It reads a page as it downloads: `scan(_:isComplete:)` stops before anything whose end has
/// not arrived yet and carries on from there on the next call, so the download can stop as soon
/// as what previews need is in (`isFinished`). Positions are byte offsets into the page;
/// nothing is decoded here.
///
/// A browser's parser also ends the head on its own at the first thing a head cannot hold — a
/// `<div>`, text — and puts everything after it in the body, `</head>` or not. Each element
/// says which side of that point it is on: Link Presentation reads `<meta>` anywhere but takes
/// icons only from the head (YouTube's icon links, 540 KB into a head a `<div>` ended at
/// 6.5 KB, are not its icons).
struct HTMLHeadScanner {
    /// A `<meta>`, `<link>` or `<base>`.
    struct Element: Equatable {
        /// In lower case.
        let name: String
        let attributes: [Attribute]
        /// Whether a browser's parser puts it in the head.
        var isInHead = true

        func value(of name: String) -> Range<Int>? {
            attributes.first { $0.name == name }?.value
        }
    }

    struct Attribute: Equatable {
        /// In lower case.
        let name: String
        /// Where the value is, without its quotes; empty for an attribute without one.
        let value: Range<Int>
    }

    /// Where the text of the first `<title>` is, before its references are decoded.
    private(set) var title: Range<Int>?
    private(set) var elements: [Element] = []
    /// Whether `</head>` has been read; after it only a `<title>` is looked for.
    private(set) var hasReachedEndOfHead = false
    /// Whether the head has an `og:title` or `twitter:title`.
    private(set) var hasTitleTag = false

    /// Whether what previews need is in: the head, and a title of some kind.
    var isFinished: Bool {
        hasReachedEndOfHead && (title != nil || hasTitleTag)
    }
    /// Whether the parser has left the head, by `</head>` or by meeting what a head cannot hold.
    private(set) var hasLeftHead = false

    /// Where the next call starts reading.
    private var position = 0
    /// Depth of `<svg>` and `<math>`: a `<title>` in them names a drawing, not the page.
    private var foreignDepth = 0

    /// Reads `bytes` — the page so far, from its start — from where the last call stopped.
    /// `isComplete` says no more bytes will come: whatever is still open runs to the end.
    mutating func scan(_ bytes: UnsafeRawBufferPointer, isComplete: Bool) {
        let reader = Reader(bytes: bytes, isComplete: isComplete)
        while !isFinished {
            guard let open = reader.index(of: .lessThan, from: position) else {
                noteText(position..<bytes.count, with: reader)
                position = bytes.count
                return
            }
            noteText(position..<open, with: reader)
            guard let next = readConstruct(at: open, with: reader) else {
                // Its end has not arrived; read it again whole next time.
                position = open
                return
            }
            position = next
        }
    }

    /// Reads what starts with the `<` at `open`. Returns where reading goes on, or `nil` when the
    /// construct ends beyond the bytes there are and more are coming.
    private mutating func readConstruct(at open: Int, with reader: Reader) -> Int? {
        let first = open + 1
        guard let byte = reader.byte(at: first) else { return reader.unfinished }
        switch byte {
        case .exclamationMark:
            // Whether it is a comment cannot be told from `<!` or `<!-` alone.
            guard first + 2 < reader.count || reader.isComplete else { return nil }
            if reader.matches("--", at: first + 1) {
                return reader.endOfComment(from: first + 3)
            }
            // A doctype, CDATA or any other declaration ends at the next `>`.
            return reader.after(.greaterThan, from: first)
        case .questionMark:
            return reader.after(.greaterThan, from: first)
        case .slash:
            return readEndTag(from: first + 1, with: reader)
        case let byte where byte.isASCIILetter:
            return readStartTag(from: first, with: reader)
        default:
            // A `<` that opens nothing is text.
            hasLeftHead = true
            return first
        }
    }

    /// Whether a `<meta>` is an `og:title` or `twitter:title`, by `property` or `name`.
    private static func namesATitle(_ tag: Reader.StartTag, with reader: Reader) -> Bool {
        tag.attributes.contains { attribute in
            (attribute.name == "property" || attribute.name == "name")
                && ["og:title", "twitter:title"].contains(reader.lowercased(attribute.value))
        }
    }

    /// Text that is not white space has no place in a head: the body starts there.
    private mutating func noteText(_ range: Range<Int>, with reader: Reader) {
        guard !hasLeftHead, range.contains(where: { !reader.bytes[$0].isHTMLSpace }) else { return }
        hasLeftHead = true
    }

    /// What a head can hold; any other start tag ends it.
    private static let headElements: Set<String> = [
        "html", "head", "base", "basefont", "bgsound", "link", "meta", "title", "noscript", "noframes", "style", "script", "template",
    ]

    private mutating func readEndTag(from nameStart: Int, with reader: Reader) -> Int? {
        guard let first = reader.byte(at: nameStart) else { return reader.unfinished }
        guard first.isASCIILetter else {
            // `</>` is dropped; `</ …>` is a comment.
            return reader.after(.greaterThan, from: nameStart)
        }
        guard let close = reader.index(of: .greaterThan, from: nameStart) else { return reader.unfinished }
        let name = reader.tagName(from: nameStart, before: close)
        switch name {
        case "head":
            hasReachedEndOfHead = true
            hasLeftHead = true
        case "body", "html", "br":
            hasLeftHead = true
        case "svg", "math":
            foreignDepth = max(0, foreignDepth - 1)
        default:
            break
        }
        return close + 1
    }

    private mutating func readStartTag(from nameStart: Int, with reader: Reader) -> Int? {
        guard let tag = reader.startTag(from: nameStart) else { return reader.unfinished }
        if !Self.headElements.contains(tag.name) {
            hasLeftHead = true
        }
        switch tag.name {
        case "title" where foreignDepth == 0:
            guard let text = reader.rawText(closedBy: "title", from: tag.end) else { return reader.unfinished }
            if title == nil {
                title = text.content
            }
            return text.end
        case "script", "style", "textarea", "xmp", "iframe", "noembed", "noframes":
            // Their text is not markup: a `<meta>` or `<title>` in a script string is not one.
            return reader.rawText(closedBy: tag.name, from: tag.end)?.end ?? reader.unfinished
        case "plaintext":
            // Everything after it is text.
            return reader.isComplete ? reader.count : nil
        case "svg", "math":
            if !tag.isSelfClosing {
                foreignDepth += 1
            }
        case "meta", "link", "base":
            guard !hasReachedEndOfHead else { break }
            elements.append(Element(name: tag.name, attributes: tag.attributes, isInHead: !hasLeftHead))
            if tag.name == "meta", Self.namesATitle(tag, with: reader) {
                hasTitleTag = true
            }
        default:
            break
        }
        return tag.end
    }
}

extension HTMLHeadScanner {
    /// Byte-level reading of the page there is so far.
    private struct Reader {
        let bytes: UnsafeRawBufferPointer
        let isComplete: Bool

        var count: Int { bytes.count }

        /// Where reading goes on when a construct is cut off by the end of the bytes: at the end
        /// when no more come, or nowhere yet.
        var unfinished: Int? { isComplete ? count : nil }

        func byte(at index: Int) -> UInt8? {
            index < count ? bytes[index] : nil
        }

        func index(of byte: UInt8, from start: Int) -> Int? {
            guard start < count, let base = bytes.baseAddress,
                  let found = memchr(base + start, Int32(byte), count - start)
            else { return nil }
            return base.distance(to: UnsafeRawPointer(found))
        }

        /// The index after the next `byte`, or what an unfinished construct gets.
        func after(_ byte: UInt8, from start: Int) -> Int? {
            index(of: byte, from: start).map { $0 + 1 } ?? unfinished
        }

        func matches(_ text: StaticString, at start: Int) -> Bool {
            let length = text.utf8CodeUnitCount
            guard start + length <= count else { return false }
            for offset in 0..<length where bytes[start + offset] != text.utf8Start[offset] {
                return false
            }
            return true
        }

        /// The index after the comment whose text starts at `start` (just past `<!--`). `<!-->`
        /// and `<!--->` are empty comments, as in HTML.
        func endOfComment(from start: Int) -> Int? {
            if byte(at: start) == .greaterThan { return start + 1 }
            if byte(at: start) == .hyphen, byte(at: start + 1) == .greaterThan { return start + 2 }
            var search = start
            while let hyphen = index(of: .hyphen, from: search) {
                if byte(at: hyphen + 1) == .hyphen, byte(at: hyphen + 2) == .greaterThan {
                    return hyphen + 3
                }
                search = hyphen + 1
            }
            return unfinished
        }

        /// The name of a tag, in lower case, up to a space, `/` or `end`.
        func tagName(from start: Int, before end: Int) -> String {
            var index = start
            while index < end, !bytes[index].isHTMLSpace, bytes[index] != .slash {
                index += 1
            }
            return lowercased(start..<index)
        }

        func lowercased(_ range: Range<Int>) -> String {
            String(decoding: bytes[range].lazy.map { $0.isASCIIUpperLetter ? $0 | 0x20 : $0 }, as: UTF8.self)
        }

        struct StartTag {
            let name: String
            let attributes: [Attribute]
            let isSelfClosing: Bool
            /// The index after its `>`.
            let end: Int
        }

        /// The start tag whose name starts at `nameStart`; `nil` when its `>` has not arrived.
        /// Attributes follow HTML's tokenizer: a repeated name keeps its first value, and an
        /// unquoted value runs to a space or `>`.
        func startTag(from nameStart: Int) -> StartTag? {
            var index = nameStart
            while index < count, !bytes[index].isHTMLSpace, bytes[index] != .slash, bytes[index] != .greaterThan {
                index += 1
            }
            let name = lowercased(nameStart..<index)
            var attributes: [Attribute] = []
            var isSelfClosing = false
            while true {
                while index < count, bytes[index].isHTMLSpace || bytes[index] == .slash {
                    isSelfClosing = bytes[index] == .slash
                    index += 1
                }
                guard index < count else { return nil }
                if bytes[index] == .greaterThan {
                    return StartTag(name: name, attributes: attributes, isSelfClosing: isSelfClosing, end: index + 1)
                }
                isSelfClosing = false
                // The first character of a name can be anything, `=` included.
                let attributeStart = index
                index += 1
                while index < count, !bytes[index].isHTMLSpace, bytes[index] != .slash,
                      bytes[index] != .greaterThan, bytes[index] != .equalsSign {
                    index += 1
                }
                let attributeName = lowercased(attributeStart..<index)
                while index < count, bytes[index].isHTMLSpace {
                    index += 1
                }
                guard index < count else { return nil }
                var value = index..<index
                if bytes[index] == .equalsSign {
                    index += 1
                    while index < count, bytes[index].isHTMLSpace {
                        index += 1
                    }
                    guard index < count else { return nil }
                    let quote = bytes[index]
                    if quote == .quotationMark || quote == .apostrophe {
                        guard let close = self.index(of: quote, from: index + 1) else { return nil }
                        value = index + 1..<close
                        index = close + 1
                    } else if quote != .greaterThan {
                        let valueStart = index
                        while index < count, !bytes[index].isHTMLSpace, bytes[index] != .greaterThan {
                            index += 1
                        }
                        value = valueStart..<index
                    }
                }
                if !attributes.contains(where: { $0.name == attributeName }) {
                    attributes.append(Attribute(name: attributeName, value: value))
                }
            }
        }

        /// The text of a `<title>`, `<script>`, `<style>`… from `start` up to its end tag, and the
        /// index after that tag. Without an end tag, the text runs to the end of a complete page.
        func rawText(closedBy name: String, from start: Int) -> (content: Range<Int>, end: Int)? {
            let length = name.utf8.count
            var search = start
            while let open = index(of: .lessThan, from: search) {
                let nameStart = open + 2
                guard nameStart + length <= count else { break }
                if bytes[open + 1] == .slash,
                   zip(bytes[nameStart..<nameStart + length], name.utf8).allSatisfy({ $0 | 0x20 == $1 }) {
                    guard let after = byte(at: nameStart + length) else { break }
                    if after.isHTMLSpace || after == .slash || after == .greaterThan {
                        guard let close = index(of: .greaterThan, from: nameStart + length) else { break }
                        return (start..<open, close + 1)
                    }
                }
                search = open + 1
            }
            return isComplete ? (start..<count, count) : nil
        }
    }
}

private extension UInt8 {
    static let lessThan = UInt8(ascii: "<")
    static let greaterThan = UInt8(ascii: ">")
    static let slash = UInt8(ascii: "/")
    static let exclamationMark = UInt8(ascii: "!")
    static let questionMark = UInt8(ascii: "?")
    static let hyphen = UInt8(ascii: "-")
    static let equalsSign = UInt8(ascii: "=")
    static let quotationMark = UInt8(ascii: "\"")
    static let apostrophe = UInt8(ascii: "'")

    var isASCIILetter: Bool {
        isASCIIUpperLetter || (UInt8(ascii: "a")...UInt8(ascii: "z")).contains(self)
    }

    var isASCIIUpperLetter: Bool {
        (UInt8(ascii: "A")...UInt8(ascii: "Z")).contains(self)
    }

    /// HTML's whitespace: tab, line feed, form feed, carriage return and space.
    var isHTMLSpace: Bool {
        self == 0x20 || self == 0x09 || self == 0x0A || self == 0x0C || self == 0x0D
    }
}
