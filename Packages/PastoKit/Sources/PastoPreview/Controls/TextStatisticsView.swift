import AppKit
import PastoCoreUI

/// The character, word and line counts of a text, side by side with a faint dot between each
/// two. It shows the text it was created with.
final class TextStatisticsView: NSStackView {
    init(text: String) {
        super.init(frame: .zero)
        orientation = .horizontal
        spacing = PreviewMetrics.statisticsSpacing

        let statistics = TextStatistics(of: text)
        let captions = [
            PreviewStrings.characterCount(statistics.characters),
            PreviewStrings.wordCount(statistics.words),
            PreviewStrings.lineCount(statistics.lines),
        ]
        for (index, caption) in captions.enumerated() {
            if index > 0 {
                addArrangedSubview(Self.makeSeparator())
            }
            let label = NSTextField(labelWithString: caption)
            // Fixed-width digits keep the counts from shifting while the user types.
            label.font = .monospacedDigitSystemFont(ofSize: NSFont.preferredFont(forTextStyle: .body).pointSize, weight: .regular)
            label.textColor = ItemPresentation.secondaryTextColor
            addArrangedSubview(label)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("TextStatisticsView is created in code")
    }

    /// A label in the default font, unlike the counts.
    private static func makeSeparator() -> NSTextField {
        let separator = NSTextField(labelWithString: PreviewMetrics.statisticsSeparator)
        separator.textColor = PreviewColor.ink(PreviewMetrics.statisticsSeparatorOpacity)
        return separator
    }
}
