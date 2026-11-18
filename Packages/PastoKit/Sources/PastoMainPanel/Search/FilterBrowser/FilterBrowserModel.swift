import Observation
import PastoSearch

/// The state of the filter browser: every filter there is, which ones the query has, which long
/// sections are open and where the keyboard highlight is.
@Observable
final class FilterBrowserModel {
    private(set) var query: SearchQuery
    private(set) var expandedSections: Set<SearchFilterType> = []
    /// The entry the keyboard highlight is on, counted across all sections; nil until a key
    /// brings it in.
    private(set) var highlightedIndex: Int?

    @ObservationIgnored private let availableFilters: [SearchFilterType: [SearchSuggestion]]
    @ObservationIgnored private let hidesAppliedFilters: Bool
    @ObservationIgnored let icon: (SearchFilter) -> SearchFilterIcon
    @ObservationIgnored private let onQueryChanged: (SearchQuery) -> Void
    @ObservationIgnored private let onClose: () -> Void

    /// - Parameters:
    ///   - hidesAppliedFilters: Leave the filters the query already has out of the browser.
    ///   - onQueryChanged: The user added a filter to the query or removed one from it.
    ///   - onClose: The browser asks to be closed.
    init(
        query: SearchQuery,
        availableFilters: [SearchFilterType: [SearchSuggestion]],
        hidesAppliedFilters: Bool,
        icon: @escaping (SearchFilter) -> SearchFilterIcon,
        onQueryChanged: @escaping (SearchQuery) -> Void,
        onClose: @escaping () -> Void
    ) {
        self.query = query
        self.availableFilters = availableFilters
        self.hidesAppliedFilters = hidesAppliedFilters
        self.icon = icon
        self.onQueryChanged = onQueryChanged
        self.onClose = onClose
    }

    var sections: [FilterBrowserSection] {
        FilterBrowserContent.sections(
            available: availableFilters,
            query: query,
            hidesApplied: hidesAppliedFilters,
            expanded: expandedSections
        )
    }

    /// The identifier of the highlighted entry, to scroll it into view.
    var highlightedEntryID: FilterBrowserSection.Entry.ID? {
        highlightedIndex.flatMap { index in
            let entries = sections.flatMap(\.entries)
            return entries.indices.contains(index) ? entries[index].id : nil
        }
    }

    // MARK: - Actions

    /// The user chose an entry, with the mouse or with Return.
    ///
    /// - Parameter keepsOpen: ⌘ is held: a filter is toggled without closing the browser.
    func activate(_ entry: FilterBrowserSection.Entry, keepsOpen: Bool) {
        switch entry {
        case .filter(let suggestion, _):
            query = FilterBrowserContent.toggling(suggestion.filter, in: query)
            onQueryChanged(query)
            if !keepsOpen { onClose() }
        case .disclosure(let type, _):
            expandedSections.formSymmetricDifference([type])
        }
    }

    /// Return: acts on the highlighted entry, if there is one.
    func activateHighlighted(keepsOpen: Bool) {
        let entries = sections.flatMap(\.entries)
        guard let index = highlightedIndex, entries.indices.contains(index) else { return }
        activate(entries[index], keepsOpen: keepsOpen)
    }

    func moveHighlight(_ direction: FilterBrowserNavigation.Direction) {
        highlightedIndex = FilterBrowserNavigation.index(
            from: highlightedIndex,
            moving: direction,
            sectionSizes: sections.map(\.entries.count)
        )
    }

    func close() {
        onClose()
    }
}
