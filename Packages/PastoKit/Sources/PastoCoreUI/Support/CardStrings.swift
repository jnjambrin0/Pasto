import Foundation
import PastoCore

/// The user-visible strings of the cards (Resources/Localizable.xcstrings).
nonisolated struct CardStrings: Sendable {
    private let bundle: Bundle
    /// Formats the numbers inside the strings (grouping separators, digits).
    private let locale: Locale

    /// The strings in the user's language.
    init() {
        bundle = .module
        locale = .autoupdatingCurrent
    }

    /// The strings in one given language, whatever the user's preferences are. `nil` if the
    /// module has no localization for it.
    init?(languageCode: String) {
        guard let path = Bundle.module.path(forResource: languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path)
        else { return nil }
        self.bundle = bundle
        locale = Locale(identifier: languageCode)
    }

    /// The name a card shows as its title while the user has not given it one. `fileCount` only
    /// matters for file items.
    func typeName(for type: ItemType, fileCount: Int = 1) -> String {
        switch type {
        case .text: string("card.type.text")
        case .link: string("card.type.link")
        case .image: string("card.type.image")
        case .color: string("card.type.color")
        case .files: format("card.type.files", max(fileCount, 1))
        case .unknown: string("card.type.unknown")
        }
    }

    func characterCount(_ count: Int) -> String {
        format("card.text.characterCount", count)
    }

    var multipleFiles: String { string("card.files.multiple") }
    var justNow: String { string("card.date.justNow") }
    var previewUnavailable: String { string("card.unknown.previewUnavailable") }

    private func string(_ key: String) -> String {
        bundle.localizedString(forKey: key, value: nil, table: nil)
    }

    private func format(_ key: String, _ count: Int) -> String {
        String(format: string(key), locale: locale, count)
    }
}
