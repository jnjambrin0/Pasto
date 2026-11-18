import Foundation
import PastoSearch

extension NSAttributedString.Key {
    /// On the attachment character of a filter token: the `SearchFilter` it stands for.
    nonisolated static let searchFilter = NSAttributedString.Key("pastoSearchFilter")
}

/// Translates between the search field's content — text with one attachment character per
/// filter token — and the query it spells.
nonisolated enum SearchFieldText {
    /// The character an attachment occupies in the text.
    static let attachmentCharacter: Character = "\u{FFFC}"

    /// The query `text` spells, in the order it is written; the caller normalizes it.
    ///
    /// Only an attachment character marked with a filter is a filter. Text typed next to a token
    /// can inherit the token's mark, so within a marked run anything else is still text.
    static func query(in text: NSAttributedString) -> SearchQuery {
        var components: [SearchQuery.Component] = []
        var pendingText = ""
        func flushText() {
            // An attachment character without a filter is not a token: it reads as a space.
            let plain = pendingText.replacing(String(attachmentCharacter), with: " ")
            components += SearchQuery.tokens(inFieldText: plain)
            pendingText = ""
        }

        let string = text.string as NSString
        text.enumerateAttribute(.searchFilter, in: NSRange(location: 0, length: text.length)) { value, range, _ in
            let run = string.substring(with: range)
            guard let filter = value as? SearchFilter else {
                pendingText += run
                return
            }
            for character in run {
                if character == attachmentCharacter {
                    flushText()
                    components.append(.filter(filter))
                } else {
                    pendingText.append(character)
                }
            }
        }
        flushText()
        return SearchQuery(components: components)
    }

    /// The field's content for `query`: its text with `textAttributes`, and for every filter
    /// whatever `token` returns — one attachment character — marked with the filter.
    static func attributedString(
        for query: SearchQuery,
        textAttributes: [NSAttributedString.Key: Any],
        token: (SearchFilter) -> NSAttributedString
    ) -> NSAttributedString {
        let result = NSMutableAttributedString()
        for component in query.components {
            switch component {
            case .token(let text):
                result.append(NSAttributedString(string: text, attributes: textAttributes))
            case .filter(let filter):
                let marked = NSMutableAttributedString(attributedString: token(filter))
                marked.addAttribute(.searchFilter, value: filter, range: NSRange(location: 0, length: marked.length))
                result.append(marked)
            }
        }
        return result
    }

    /// Text pasted into the field's single line: every line feed and every carriage return
    /// becomes a space — two for a CRLF pair —, and other line separators stay.
    static func singleLine(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        scalars.append(contentsOf: text.unicodeScalars.map { $0 == "\n" || $0 == "\r" ? " " : $0 })
        return String(scalars)
    }

    /// How many UTF-16 units `component` takes in the field: a filter is one attachment character.
    static func length(of component: SearchQuery.Component) -> Int {
        switch component {
        case .token(let text): text.utf16.count
        case .filter: 1
        }
    }

    static func length(of query: SearchQuery) -> Int {
        query.components.reduce(0) { $0 + length(of: $1) }
    }
}
