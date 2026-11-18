import AppKit

/// The four kinds of formatting the text editor keeps.
nonisolated enum TextTrait: CaseIterable, Sendable {
    case bold
    case italic
    case underline
    case strikethrough

    /// Whether a run with these attributes has the trait. Only a single line counts as
    /// underlined or struck through.
    func isActive(in attributes: [NSAttributedString.Key: Any]) -> Bool {
        switch self {
        case .bold, .italic:
            guard let font = attributes[.font] as? NSFont, let fontTrait else { return false }
            return font.fontDescriptor.symbolicTraits.contains(fontTrait)
        case .underline, .strikethrough:
            return attributes[lineKey] as? Int == NSUnderlineStyle.single.rawValue
        }
    }

    /// Gives the trait to `attributes` or takes it away. Bold and italic keep the font's family
    /// and size; a family without that variant is left as it is.
    func set(_ isOn: Bool, in attributes: inout [NSAttributedString.Key: Any]) {
        switch self {
        case .bold, .italic:
            guard let fontTrait else { return }
            let font = attributes[.font] as? NSFont ?? EditableText.baseFont
            var traits = font.fontDescriptor.symbolicTraits
            if isOn { traits.insert(fontTrait) } else { traits.remove(fontTrait) }
            attributes[.font] = NSFont(descriptor: font.fontDescriptor.withSymbolicTraits(traits), size: font.pointSize) ?? font
        case .underline, .strikethrough:
            attributes[lineKey] = isOn ? NSUnderlineStyle.single.rawValue : nil
        }
    }

    private var fontTrait: NSFontDescriptor.SymbolicTraits? {
        switch self {
        case .bold: .bold
        case .italic: .italic
        case .underline, .strikethrough: nil
        }
    }

    private var lineKey: NSAttributedString.Key {
        self == .strikethrough ? .strikethroughStyle : .underlineStyle
    }
}
