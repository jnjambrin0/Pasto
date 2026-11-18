import AppKit
import PastoUI

/// The card of a text item: the text as it is, running off the bottom of the card behind a fade,
/// and a character count.
///
/// Rich text keeps its own fonts and colours; plain text is set in the body font. There is no
/// monospaced or syntax-coloured treatment for code. The card's background follows the text:
/// near black or white for plain text, the text's own dominant background for rich text.
public final class TextItemCell: ItemCell {
    private let previewLabel = NSTextField(labelWithAttributedString: NSAttributedString())
    private let footerView = TextFooterView(frame: .zero)

    /// Gap between the top of the body and the text. It moves during a density transition.
    private var textTopInset = CardContentMetrics.topInset

    public required init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        previewLabel.maximumNumberOfLines = 0
        previewLabel.alignment = .natural
        // What the text itself does not specify falls back to these.
        previewLabel.font = CardFont.body.font
        previewLabel.textColor = CardTextColor.primary.color

        bodyView.addSubview(previewLabel)
        bodyView.addSubview(footerView)
        footerView.onHeightChange = { [weak self] in self?.needsLayout = true }
    }

    override func configureContent(with model: ItemCellModel, environment: ItemCellEnvironment) {
        guard case .text(let text) = model.content else {
            previewLabel.stringValue = ""
            footerView.caption = ""
            cardBackground = .plainText
            return
        }
        previewLabel.attributedStringValue = text.attributedText
        footerView.caption = CardStrings().characterCount(text.characterCount)
        updateBackground()
    }

    /// The rule depends on the system mode (text without a colour of its own is light in dark
    /// mode), so it is applied again when the mode changes.
    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        guard case .text(let text) = model?.content else { return }
        cardBackground = TextCardBackground.resolve(text.background, isDark: effectiveAppearance.isDark)
        footerView.fadingColor = resolvedBackgroundColor
    }

    // MARK: - Density

    private static func textTopInset(for sizeClass: SizeClass) -> CGFloat {
        sizeClass == .compact ? 0 : CardContentMetrics.topInset
    }

    override func applyContentLayout(for sizeClass: SizeClass) {
        textTopInset = Self.textTopInset(for: sizeClass)
        footerView.setCompact(sizeClass == .compact, animated: false)
    }

    override func transitionContent(to destination: SizeClass, progress: Double) {
        textTopInset = textTopInset.approaching(Self.textTopInset(for: destination), progress: progress)
        footerView.setCompact(destination == .compact, animated: true)
    }

    // MARK: - Layout

    override func layoutContent(in bounds: CGRect) {
        let inset = CardContentMetrics.sideInset
        // The label may run past the card's bottom edge, where the card clips it: the text is
        // never measured, only drawn from the top for as long as there is room.
        previewLabel.setAlignmentRect(CGRect(
            x: inset,
            y: textTopInset,
            width: bounds.width - 2 * inset,
            height: bounds.height - textTopInset + CardContentMetrics.bottomInset
        ))

        let footerHeight = footerView.height
        footerView.frame = CGRect(x: 0, y: bounds.height - footerHeight, width: bounds.width, height: footerHeight)
    }
}
