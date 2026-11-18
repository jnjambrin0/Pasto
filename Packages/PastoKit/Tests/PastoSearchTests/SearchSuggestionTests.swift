import Foundation
import PastoCore
@testable import PastoSearch
import Testing

struct WordPrefixMatcherTests {
    private func matched(_ typed: String, in candidate: String) -> [String]? {
        WordPrefixMatcher.matchedRanges(of: typed, in: candidate)?.map { String(candidate[$0]) }
    }

    @Test func everyTypedWordStartsAWordInOrder() {
        #expect(matched("la 30", in: "Last 30 days") == ["La", "30"])
        #expect(matched("days", in: "Last 30 days") == ["days"])
        #expect(matched("30 la", in: "Last 30 days") == nil)
        #expect(matched("ast", in: "Last 30 days") == nil)
    }

    @Test func caseAndDiacriticsDoNotCount() {
        #expect(matched("cafe", in: "Mi Café") == ["Café"])
        #expect(matched("XC", in: "Xcode") == ["Xc"])
    }

    @Test func aLaterOccurrenceThatStartsAWordCounts() {
        #expect(matched("ma", in: "Email Mail") == ["Ma"])
        #expect(matched("code", in: "Xcode VS-Code") == ["Code"])
    }

    @Test func nothingTypedMatchesNothing() {
        #expect(matched("  ", in: "Mail") == nil)
    }
}

@MainActor
struct SearchSuggesterTests {
    private struct Source: SearchSuggestionDataSource {
        var applications = ["Mail", "Maps", "Safari"]
        var devices = ["Mac mini", "iPhone"]
        var boards = [SearchSuggestionPinboard(id: ListID(rawValue: "P1"), name: "Marketing")]

        func applicationNames() -> [String] { applications }
        func deviceNames() -> [String] { devices }
        func pinboards() -> [SearchSuggestionPinboard] { boards }
    }

    private func suggester(_ source: Source = Source()) -> SearchSuggester {
        SearchSuggester(
            dataSource: source,
            calendar: {
                var calendar = Calendar(identifier: .gregorian)
                calendar.timeZone = TimeZone(identifier: "UTC")!
                return calendar
            },
            now: { Date(timeIntervalSince1970: 86400 * 10 + 60) }
        )
    }

    @Test func sourcesAreAskedInOrder() {
        let suggestions = suggester().suggestions(for: .token(" ma "), in: SearchQuery(text: "ma"))
        #expect(suggestions.map(\.title) == ["Mail", "Maps", "Mac mini", "Marketing"])
        #expect(suggestions.map(\.filter.type) == [.app, .app, .device, .pinboard])
        #expect(suggestions.last?.filter.value == "P1")
        #expect(suggestions.first.map { String($0.title[$0.matchedRanges[0]]) } == "Ma")
    }

    @Test func typesMatchByTheirStartAndDatesByWord() {
        #expect(suggester().suggestions(for: .token("l"), in: SearchQuery()).map(\.title)
            == ["Link", "Last week", "Last 30 days"])
        #expect(suggester().suggestions(for: .token("30"), in: SearchQuery()).map(\.filter)
            == [SearchFilter(type: .date, value: "\(86400 * -20) \(86400 * 11)")])
    }

    @Test func filtersAlreadyAppliedAreNotOfferedAgain() {
        let query = SearchQuery(components: [.filter(SearchFilter(type: .app, value: "Mail")), .token("ma")])
        #expect(suggester().suggestions(for: .token("ma"), in: query).map(\.title) == ["Maps", "Mac mini", "Marketing"])
    }

    @Test func filtersAndBlanksGetNoSuggestions() {
        #expect(suggester().suggestions(for: .token("  "), in: SearchQuery()).isEmpty)
        #expect(suggester().suggestions(for: .filter(SearchFilter(type: .app, value: "Mail")), in: SearchQuery()).isEmpty)
    }

    @Test func eachSourceContributesAtMostThirty() {
        var source = Source()
        source.applications = (1...40).map { "App \($0)" }
        source.devices = []
        source.boards = []
        #expect(suggester(source).suggestions(for: .token("app"), in: SearchQuery()).count == 30)
    }

    @Test func theBrowserGetsEveryFilterByType() {
        let filters = suggester().availableFilters()
        #expect(filters[.type]?.map(\.title) == ["Unknown", "Image", "Color", "File", "Link", "Text"])
        #expect(filters[.app]?.map(\.title) == ["Mail", "Maps", "Safari"])
        #expect(filters[.device]?.map(\.title) == ["Mac mini", "iPhone"])
        #expect(filters[.pinboard]?.map(\.filter.value) == ["P1"])
        #expect(filters[.date]?.map(\.title) == SearchDatePreset.allCases.map(\.name))
        #expect(filters[.title] == nil)
    }
}
