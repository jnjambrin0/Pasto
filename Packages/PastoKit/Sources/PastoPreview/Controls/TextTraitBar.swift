import AppKit
import PastoUI

/// The four formatting buttons of the text editor: bold, italic, underline and strikethrough,
/// the first three with the usual ⌘B, ⌘I and ⌘U.
final class TextTraitBar: NSStackView {
    var onToggle: ((TextTrait) -> Void)?

    /// The traits whose buttons show as on.
    var activeTraits: Set<TextTrait> = [] {
        didSet {
            for (trait, button) in buttons {
                button.isSelected = activeTraits.contains(trait)
            }
        }
    }

    private var buttons: [TextTrait: PreviewButton] = [:]

    init() {
        super.init(frame: .zero)
        orientation = .horizontal
        translatesAutoresizingMaskIntoConstraints = false

        for trait in TextTrait.allCases {
            let button = PreviewButton(symbolName: trait.symbolName, accessibilityLabel: trait.label)
            button.toolTip = trait.label
            button.isToggle = true
            button.keyEquivalent = trait.keyCharacter.map { KeyEquivalent($0, modifiers: .command) }
            button.onClick = { [weak self] _ in self?.onToggle?(trait) }
            buttons[trait] = button
            addArrangedSubview(button)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextTraitBar is created in code")
    }
}

private extension TextTrait {
    var symbolName: String {
        switch self {
        case .bold: "bold"
        case .italic: "italic"
        case .underline: "underline"
        case .strikethrough: "strikethrough"
        }
    }

    var label: String {
        switch self {
        case .bold: PreviewStrings.bold
        case .italic: PreviewStrings.italic
        case .underline: PreviewStrings.underline
        case .strikethrough: PreviewStrings.strikethrough
        }
    }

    /// Strikethrough has no shortcut.
    var keyCharacter: String? {
        switch self {
        case .bold: "b"
        case .italic: "i"
        case .underline: "u"
        case .strikethrough: nil
        }
    }
}
