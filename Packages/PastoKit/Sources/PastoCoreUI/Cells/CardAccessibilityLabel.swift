import Foundation

/// What VoiceOver reads for a card: its title, when and where it was copied, and the start of
/// its content, as in "Text, copied 5 minutes ago from Safari: Dear Ana, …". The strings are in
/// `Resources/Localizable.xcstrings`.
nonisolated struct CardAccessibilityLabel {
    /// How much of a text, a link or a list of files is read out.
    static let excerptLength = 120

    private let bundle: Bundle

    /// The strings in the user's language.
    init() {
        bundle = .module
    }

    /// The strings in one given language, whatever the user's preferences are. `nil` if the
    /// module has no localization for it.
    init?(languageCode: String) {
        guard let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        self.bundle = bundle
    }

    /// `relativeDate` is the header's long form ("5 minutes ago"), or `nil` where the card shows
    /// no date, inside a pinboard.
    func label(for model: ItemCellModel, relativeDate: String?) -> String {
        let applicationName = model.sourceApplication?.name
        var label: String
        switch (relativeDate, applicationName) {
        case let (date?, application?):
            label = format("card.accessibility.dateAndApplication", model.title, date, application)
        case let (date?, nil):
            label = format("card.accessibility.date", model.title, date)
        case let (nil, application?):
            label = format("card.accessibility.application", model.title, application)
        case (nil, nil):
            label = model.title
        }
        if let summary = Self.summary(of: model.content) {
            label = format("card.accessibility.content", label, summary)
        }
        return label
    }

    /// The content in a few words: the start of a text, a link's title or address, an image's
    /// size, a colour's code, the files' names. `nil` when there is nothing to read.
    static func summary(of content: ItemCellModel.Content) -> String? {
        let summary: String
        switch content {
        case .text(let text):
            summary = excerpt(text.attributedText.string)
        case .link(let link):
            summary = excerpt(link.title.flatMap { $0.isEmpty ? nil : $0 } ?? link.url.absoluteString)
        case .image(let image):
            summary = "\(image.width) × \(image.height)"
        case .color(let code):
            summary = code.hexString
        case .files(let files):
            summary = excerpt(files.paths.map { ($0 as NSString).lastPathComponent }.joined(separator: ", "))
        case .unknown:
            return nil
        }
        return summary.isEmpty ? nil : summary
    }

    /// The text with its runs of white space, line breaks included, read as one space, and cut
    /// at a word boundary after `excerptLength` characters.
    static func excerpt(_ text: String) -> String {
        let words = text.split(whereSeparator: { $0.isWhitespace || $0.isNewline })
        var result = ""
        for word in words {
            if !result.isEmpty {
                guard result.count + 1 + word.count <= excerptLength else { return result + "…" }
                result += " "
            } else if word.count > excerptLength {
                return String(word.prefix(excerptLength)) + "…"
            }
            result += word
        }
        return result
    }

    private func format(_ key: String, _ arguments: any CVarArg...) -> String {
        String(format: bundle.localizedString(forKey: key, value: nil, table: nil), arguments: arguments)
    }
}
