import AppKit

/// The reduced formatting the text editor works with: one font, and of everything a text may
/// carry only bold, italic, underline and strikethrough.
nonisolated enum EditableText {
    /// The font traits that survive.
    private static let keptTraits: NSFontDescriptor.SymbolicTraits = [.bold, .italic]
    /// The attributes that are copied as they are.
    private static let keptAttributes: [NSAttributedString.Key] = [.underlineStyle, .strikethroughStyle]

    /// The editor's font: Helvetica Neue, or the system font should it ever be missing.
    static var baseFont: NSFont {
        NSFont(name: PreviewMetrics.editorFontName, size: PreviewMetrics.editorFontSize)
            ?? .systemFont(ofSize: PreviewMetrics.editorFontSize)
    }

    /// The same characters with the editor's formatting only: colours, fonts, sizes, links,
    /// paragraph styles and attachments are dropped.
    static func normalized(_ text: NSAttributedString) -> NSAttributedString {
        let base = baseFont
        let result = NSMutableAttributedString(string: text.string, attributes: [.font: base])
        let whole = NSRange(location: 0, length: text.length)

        text.enumerateAttributes(in: whole) { attributes, range, _ in
            let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits.intersection(keptTraits) ?? []
            if !traits.isEmpty, let font = NSFont(descriptor: base.fontDescriptor.withSymbolicTraits(traits), size: base.pointSize) {
                result.addAttribute(.font, value: font, range: range)
            }
            for key in keptAttributes {
                if let value = attributes[key] {
                    result.addAttribute(key, value: value, range: range)
                }
            }
        }
        result.fixAttributes(in: whole)
        return result
    }

    /// Whether saving `text` as plain characters would lose something the editor keeps.
    static func hasFormatting(_ text: NSAttributedString) -> Bool {
        var found = false
        text.enumerateAttributes(in: NSRange(location: 0, length: text.length)) { attributes, _, stop in
            let traits = (attributes[.font] as? NSFont)?.fontDescriptor.symbolicTraits ?? []
            if !traits.isDisjoint(with: keptTraits) || keptAttributes.contains(where: { attributes[$0] != nil }) {
                found = true
                stop.pointee = true
            }
        }
        return found
    }
}
