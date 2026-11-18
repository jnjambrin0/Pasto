@_spi(Benchmarks) @testable import PastoSearch
import Testing

struct SearchQueryStringTests {
    private func filter(_ type: SearchFilterType, _ value: String) -> SearchQuery.Component {
        .filter(SearchFilter(type: type, value: value))
    }

    @Test func wordsAreOnePhraseLookedForInEveryTextAttribute() {
        let query = SearchQuery(components: [.token("meeting"), .token("  "), .token(" slides ")])
        #expect(SearchQueryString.make(for: query)
            == #"(pastoTitle = "meeting slides*"cwdt || pastoText = "meeting slides*"cwdt)"#)
    }

    @Test func filtersOfOneTypeAreAlternativesAndTypesAreAllRequired() {
        let query = SearchQuery(components: [
            filter(.app, "Mail"), filter(.type, "Link"), filter(.type, "Image"), .token("meeting"), .token("slides"),
        ])
        #expect(SearchQueryString.make(for: query)
            == #"(pastoTitle = "meeting slides*"cwdt || pastoText = "meeting slides*"cwdt)"#
            + #" && pastoApp == "Mail"cd && (pastoType == "Link"cd || pastoType == "Image"cd)"#)
    }

    @Test func eachFilterTypeHasItsClause() {
        #expect(SearchQueryString.make(for: SearchQuery(components: [filter(.pinboard, " ABC-1 ")])) == #"pastoPinboard == "ABC-1"cd"#)
        #expect(SearchQueryString.make(for: SearchQuery(components: [filter(.title, "notes")])) == #"pastoTitle == "*notes*"cd"#)
        #expect(SearchQueryString.make(for: SearchQuery(components: [filter(.device, "MacBook")])) == #"pastoDevice == "*MacBook*"cd"#)
        #expect(SearchQueryString.make(for: SearchQuery(components: [filter(.date, "0 86400")]))
            == "(contentModificationDate >= $time.iso(1970-01-01T00:00:00Z) && contentModificationDate < $time.iso(1970-01-02T00:00:00Z))")
    }

    @Test func specialCharactersAreEscapedBackslashFirst() {
        #expect(SearchQueryString.make(for: SearchQuery(components: [filter(.app, #"a\"b*c?"#)]))
            == #"pastoApp == "a\\\"b\*c\?"cd"#)
        #expect(SearchQueryString.make(for: SearchQuery(components: [.token(#"50%*"#), .token(#""x""#)]))?
            .hasPrefix(#"(pastoTitle = "50%\* \"x\"*"cwdt"#) == true)
    }

    @Test func nothingUsableMakesNoQuery() {
        #expect(SearchQueryString.make(for: SearchQuery()) == nil)
        #expect(SearchQueryString.make(for: SearchQuery(components: [.token("  "), filter(.app, " "), filter(.date, "soon")])) == nil)
    }
}
