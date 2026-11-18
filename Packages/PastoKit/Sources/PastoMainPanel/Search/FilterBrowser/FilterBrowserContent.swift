import PastoSearch

/// One section of the filter browser: the filters of a type and, when there are many, the button
/// that shows or hides the rest.
nonisolated struct FilterBrowserSection: Equatable, Identifiable {
    enum Entry: Equatable, Identifiable {
        case filter(SearchSuggestion, isSelected: Bool)
        /// The "More" button of a collapsed section, or the "Less" one of an expanded one.
        case disclosure(SearchFilterType, isExpanded: Bool)

        var id: String {
            switch self {
            case .filter(let suggestion, _): "\(suggestion.filter.type.rawValue):\(suggestion.filter.value)"
            case .disclosure(let type, _): "\(type.rawValue)_more"
            }
        }
    }

    let type: SearchFilterType
    let entries: [Entry]

    var id: SearchFilterType { type }
}

/// What the filter browser shows and what choosing a filter does to the query.
nonisolated enum FilterBrowserContent {
    /// The order of the sections. Titles are free text, so they have no section.
    static let sectionOrder: [SearchFilterType] = [.type, .app, .pinboard, .date, .device]

    /// The sections to show: those with filters, each in the order its filters were given.
    ///
    /// - Parameters:
    ///   - hidesApplied: Leave out the filters `query` already has.
    ///   - expanded: The long sections the user has opened in full.
    static func sections(
        available: [SearchFilterType: [SearchSuggestion]],
        query: SearchQuery,
        hidesApplied: Bool,
        expanded: Set<SearchFilterType>
    ) -> [FilterBrowserSection] {
        let applied = Set(query.filters)
        return sectionOrder.compactMap { type in
            var suggestions = available[type] ?? []
            if hidesApplied {
                suggestions.removeAll { applied.contains($0.filter) }
            }
            guard !suggestions.isEmpty else { return nil }

            let isLong = suggestions.count >= SearchMetrics.Browser.collapseThreshold
            let isExpanded = expanded.contains(type)
            let shown = isLong && !isExpanded
                ? Array(suggestions.prefix(SearchMetrics.Browser.collapsedItemLimit))
                : suggestions
            var entries = shown.map { FilterBrowserSection.Entry.filter($0, isSelected: applied.contains($0.filter)) }
            if isLong {
                entries.append(.disclosure(type, isExpanded: isExpanded))
            }
            return FilterBrowserSection(type: type, entries: entries)
        }
    }

    /// `query` after the user chooses `filter`: without it if it was there, and with it at the
    /// end if it was not. Filters of the same type are not replaced; several can coexist.
    static func toggling(_ filter: SearchFilter, in query: SearchQuery) -> SearchQuery {
        var query = query
        if query.filters.contains(filter) {
            query.components.removeAll { $0 == .filter(filter) }
        } else {
            query.components.append(.filter(filter))
        }
        return query
    }
}
