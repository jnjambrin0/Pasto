import Foundation

/// What the user is searching for: filters and words, in the order they sit in the search field.
public struct SearchQuery: Sendable, Equatable {
    public enum Component: Sendable, Equatable {
        case filter(SearchFilter)
        /// A run of typed text. While the field is being edited a run of spaces is a token too,
        /// so that the field can be redrawn exactly as typed.
        case token(String)

        /// Whether it says nothing: only whitespace, or a filter with no value.
        public var isEmpty: Bool {
            switch self {
            case .filter(let filter): filter.value.trimmed.isEmpty
            case .token(let text): text.trimmed.isEmpty
            }
        }
    }

    public var components: [Component]

    public init(components: [Component] = []) {
        self.components = components
    }

    /// One token per word of `text`, split at spaces: what typing over the item strip produces.
    public init(text: String) {
        components = text.split(separator: " ").map { .token(String($0)) }
    }

    /// The tokens of text typed in the search field: alternating runs of whitespace and
    /// of anything else, each a token of its own — `"a  b "` is `"a"`, `"  "`, `"b"`, `" "`.
    public static func tokens(inFieldText text: String) -> [Component] {
        var runs: [String] = []
        var previousIsWhitespace: Bool?
        for character in text {
            if character.isWhitespace == previousIsWhitespace {
                runs[runs.count - 1].append(character)
            } else {
                runs.append(String(character))
                previousIsWhitespace = character.isWhitespace
            }
        }
        return runs.map(Component.token)
    }

    /// Whether there is nothing to search for.
    public var isEmpty: Bool {
        components.allSatisfy(\.isEmpty)
    }

    public var filters: [SearchFilter] {
        components.compactMap { component in
            if case .filter(let filter) = component { filter } else { nil }
        }
    }

    // MARK: - Normalization

    /// The query in the order the field shows it: its filters first — without the empty
    /// and the repeated ones —, then the text that followed the last filter, then the text that
    /// preceded it.
    ///
    /// - Parameter trimmingText: Trim every token and drop the empty ones. The field does not,
    ///   because its spaces are part of what the user typed.
    public func normalized(trimmingText: Bool) -> SearchQuery {
        var seen: Set<SearchFilter> = []
        let filters = self.filters.filter { !$0.value.trimmed.isEmpty && seen.insert($0).inserted }

        let lastFilterIndex = components.lastIndex { component in
            if case .filter = component { true } else { false }
        }
        let split = lastFilterIndex.map { $0 + 1 } ?? 0
        let ordered = components[split...] + components[..<split]
        let tokens = ordered.compactMap { component -> Component? in
            guard case .token(let text) = component else { return nil }
            guard trimmingText else { return component }
            let trimmed = text.trimmed
            return trimmed.isEmpty ? nil : .token(trimmed)
        }
        return SearchQuery(components: filters.map(Component.filter) + tokens)
    }

    // MARK: - Accepting a suggestion

    /// The query with the component at `index` replaced by `filter`: how the word under
    /// the cursor becomes the suggestion the user accepted. Unchanged when the query already has
    /// that filter or has no such component.
    public func replacingComponent(at index: Int, with filter: SearchFilter) -> SearchQuery {
        guard !filters.contains(filter), components.indices.contains(index) else { return self }
        var query = self
        query.components[index] = .filter(filter)
        return query
    }
}

extension StringProtocol {
    /// Without leading and trailing whitespace and newlines.
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
