import Foundation
import PastoCore

/// Offers filters: for the word the cursor is on, and all of them for the filter browser.
@MainActor
public final class SearchSuggester {
    /// How many suggestions each of applications, types, devices and pinboards may contribute.
    static let limitPerSource = 30

    private let dataSource: any SearchSuggestionDataSource
    private let calendar: @Sendable () -> Calendar
    private let now: @Sendable () -> Date

    /// - Parameters:
    ///   - calendar: The user's calendar, asked for every time: it decides where days and weeks start.
    ///   - now: The clock the date presets are computed from.
    public init(
        dataSource: any SearchSuggestionDataSource,
        calendar: @escaping @Sendable () -> Calendar = { .current },
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.dataSource = dataSource
        self.calendar = calendar
        self.now = now
    }

    /// The filters `component` — the one under the cursor — could become: applications, types,
    /// devices, pinboards and dates, in that order, without the ones `query` already has.
    /// Nothing for a filter or for blank text.
    public func suggestions(for component: SearchQuery.Component, in query: SearchQuery) -> [SearchSuggestion] {
        guard case .token(let text) = component else { return [] }
        let typed = text.trimmed
        guard !typed.isEmpty else { return [] }
        let applied = Set(query.filters)

        func matching(_ candidates: [SearchSuggestion]) -> [SearchSuggestion] {
            candidates.compactMap { candidate -> SearchSuggestion? in
                guard !applied.contains(candidate.filter),
                      let ranges = WordPrefixMatcher.matchedRanges(of: typed, in: candidate.title)
                else { return nil }
                return SearchSuggestion(filter: candidate.filter, title: candidate.title, matchedRanges: ranges)
            }
        }
        // Types are matched by how their name starts, not word by word.
        let types = matching(typeCandidates().filter {
            $0.title.range(of: typed, options: [.caseInsensitive, .anchored]) != nil
        })
        let capped = [matching(applicationCandidates()), types, matching(deviceCandidates()), matching(pinboardCandidates())]
            .flatMap { $0.prefix(Self.limitPerSource) }
        return capped + matching(dateCandidates())
    }

    /// Every filter there is to choose from, by type. There is no `title` entry: titles are free text.
    public func availableFilters() -> [SearchFilterType: [SearchSuggestion]] {
        [
            .type: typeCandidates(),
            .app: applicationCandidates(),
            .device: deviceCandidates(),
            .date: dateCandidates(),
            .pinboard: pinboardCandidates(),
        ]
    }

    // MARK: - Candidates

    private func applicationCandidates() -> [SearchSuggestion] {
        dataSource.applicationNames().map { SearchSuggestion(filter: SearchFilter(type: .app, value: $0), title: $0) }
    }

    private func typeCandidates() -> [SearchSuggestion] {
        ItemType.allCases.map { SearchSuggestion(filter: SearchFilter(type: .type, value: $0.searchName), title: $0.searchName) }
    }

    private func deviceCandidates() -> [SearchSuggestion] {
        dataSource.deviceNames().map { SearchSuggestion(filter: SearchFilter(type: .device, value: $0), title: $0) }
    }

    private func pinboardCandidates() -> [SearchSuggestion] {
        dataSource.pinboards().map {
            SearchSuggestion(filter: SearchFilter(type: .pinboard, value: $0.id.rawValue), title: $0.name)
        }
    }

    private func dateCandidates() -> [SearchSuggestion] {
        let now = now()
        let calendar = calendar()
        return SearchDatePreset.allCases.compactMap { preset in
            preset.range(now: now, calendar: calendar).map { SearchSuggestion(filter: $0.filter, title: preset.name) }
        }
    }
}
