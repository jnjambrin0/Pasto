import Foundation
import PastoSearch

/// The search interface's user-facing strings. The English and Spanish texts live in
/// `Resources/Localizable.xcstrings`; the English one is repeated here as the fallback for a
/// build that does not compile the catalog.
///
/// The names of item types and date presets are not here: they are part of the query language
/// and are not translated.
enum SearchStrings {
    static var placeholder: String { localized("search.placeholder", "Search") }
    static var clear: String { localized("search.clear", "Clear") }

    // MARK: Strip status

    static var searching: String { localized("search.status.searching", "Searching…") }
    static var nothingFound: String { localized("search.status.nothingFound", "Nothing found") }

    /// What VoiceOver says when a search finds something.
    static func resultCount(_ count: Int) -> String {
        String(localized: "search.status.resultCount", defaultValue: "\(count) results", bundle: .module)
    }

    // MARK: Filter browser

    static var filters: String { localized("search.filters.title", "Filters") }
    static var more: String { localized("search.filters.more", "More") }
    static var less: String { localized("search.filters.less", "Less") }

    /// The heading of a section of the filter browser. Titles have no section.
    static func sectionTitle(for type: SearchFilterType) -> String {
        switch type {
        case .type: localized("search.filters.section.type", "Type")
        case .app: localized("search.filters.section.app", "Application")
        case .pinboard: localized("search.filters.section.pinboard", "Pinboard")
        case .date: localized("search.filters.section.date", "Date")
        case .device: localized("search.filters.section.device", "Device")
        case .title: ""
        }
    }

    private static func localized(_ key: StaticString, _ english: String.LocalizationValue) -> String {
        String(localized: key, defaultValue: english, bundle: .module)
    }
}
