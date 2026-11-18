import Foundation

/// Writes a query in Core Spotlight's query language.
@_spi(Benchmarks)
public enum SearchQueryString {
    /// - Returns: `nil` when the query has neither text nor a usable filter: there is nothing to ask.
    public static func make(for query: SearchQuery) -> String? {
        let clauses = [textClause(for: query)].compactMap(\.self) + filterClauses(for: query)
        return clauses.isEmpty ? nil : clauses.joined(separator: " && ")
    }

    /// All the words as one phrase, looked for in every text attribute: starting a word (`*`
    /// and `w`), whatever the case and the diacritics (`c`, `d`), on tokenized values (`t`).
    private static func textClause(for query: SearchQuery) -> String? {
        let words = query.components.compactMap { component -> String? in
            guard case .token(let text) = component else { return nil }
            let trimmed = text.trimmed
            return trimmed.isEmpty ? nil : trimmed
        }
        guard !words.isEmpty else { return nil }
        let phrase = escaped(words.joined(separator: " "))
        let terms = SearchIndexAttribute.textKeys.map { "\($0) = \"\(phrase)*\"cwdt" }
        return "(\(terms.joined(separator: " || ")))"
    }

    /// One clause per filter type, in the order the types first appear: filters of one type
    /// widen each other (OR), types narrow each other (AND).
    private static func filterClauses(for query: SearchQuery) -> [String] {
        var types: [SearchFilterType] = []
        var clausesByType: [SearchFilterType: [String]] = [:]
        for filter in query.filters {
            guard let clause = clause(for: filter) else { continue }
            if clausesByType[filter.type] == nil {
                types.append(filter.type)
            }
            clausesByType[filter.type, default: []].append(clause)
        }
        return types.compactMap { type in
            guard let clauses = clausesByType[type] else { return nil }
            return clauses.count == 1 ? clauses[0] : "(\(clauses.joined(separator: " || ")))"
        }
    }

    private static func clause(for filter: SearchFilter) -> String? {
        let value = filter.value.trimmed
        guard !value.isEmpty else { return nil }
        switch filter.type {
        case .app: return "\(SearchIndexAttribute.application) == \"\(escaped(value))\"cd"
        case .type: return "\(SearchIndexAttribute.type) == \"\(escaped(value))\"cd"
        case .pinboard: return "\(SearchIndexAttribute.pinboard) == \"\(escaped(value))\"cd"
        case .title: return "\(SearchIndexAttribute.title) == \"*\(escaped(value))*\"cd"
        case .device: return "\(SearchIndexAttribute.device) == \"*\(escaped(value))*\"cd"
        case .date:
            guard let range = SearchDateRange(filterValue: value) else { return nil }
            let formatter = ISO8601DateFormatter()
            let date = SearchIndexAttribute.modificationDate
            return "(\(date) >= $time.iso(\(formatter.string(from: range.start)))"
                + " && \(date) < $time.iso(\(formatter.string(from: range.end))))"
        }
    }

    /// The backslash goes first, or it would escape the escapes.
    private static func escaped(_ text: String) -> String {
        ["\\", "\"", "*", "?"].reduce(text) { $0.replacingOccurrences(of: $1, with: "\\" + $1) }
    }
}
