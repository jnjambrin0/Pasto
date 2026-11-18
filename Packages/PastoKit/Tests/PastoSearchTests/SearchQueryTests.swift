import Foundation
@testable import PastoSearch
import Testing

struct SearchQueryTests {
    private let mail = SearchFilter(type: .app, value: "Mail")
    private let link = SearchFilter(type: .type, value: "Link")

    @Test func textBecomesOneTokenPerWord() {
        #expect(SearchQuery(text: " meeting  slides ").components == [.token("meeting"), .token("slides")])
        #expect(SearchQuery(text: "   ").components.isEmpty)
    }

    @Test func fieldTextKeepsItsSpacesAsTokens() {
        #expect(SearchQuery.tokens(inFieldText: "meeting  slides ")
            == [.token("meeting"), .token("  "), .token("slides"), .token(" ")])
        #expect(SearchQuery.tokens(inFieldText: "").isEmpty)
    }

    @Test func aQueryOfBlanksIsEmpty() {
        #expect(SearchQuery().isEmpty)
        #expect(SearchQuery(components: [.token("  "), .filter(SearchFilter(type: .app, value: " "))]).isEmpty)
        #expect(!SearchQuery(components: [.token(" "), .filter(mail)]).isEmpty)
    }

    @Test func normalizingPutsFiltersFirstThenTheTextAfterTheLastOne() {
        let query = SearchQuery(components: [
            .token("before"), .filter(mail), .token("between"), .filter(link), .token("after"),
        ])
        #expect(query.normalized(trimmingText: true).components == [
            .filter(mail), .filter(link), .token("after"), .token("before"), .token("between"),
        ])
    }

    @Test func normalizingDropsRepeatedAndEmptyFilters() {
        let query = SearchQuery(components: [
            .filter(mail), .filter(SearchFilter(type: .app, value: "  ")), .filter(mail), .token("x"),
        ])
        #expect(query.normalized(trimmingText: false).components == [.filter(mail), .token("x")])
    }

    @Test func normalizingTrimsTextOnlyWhenAsked() {
        let query = SearchQuery(components: [.token(" a "), .token("  "), .token("b")])
        #expect(query.normalized(trimmingText: true).components == [.token("a"), .token("b")])
        #expect(query.normalized(trimmingText: false) == query)
    }

    @Test func acceptingASuggestionReplacesTheWordUnderTheCursor() {
        let query = SearchQuery(components: [.token("mai"), .token(" "), .token("slides")])
        #expect(query.replacingComponent(at: 0, with: mail).components == [.filter(mail), .token(" "), .token("slides")])
        #expect(query.replacingComponent(at: 7, with: mail) == query)

        let already = SearchQuery(components: [.filter(mail), .token("mai")])
        #expect(already.replacingComponent(at: 1, with: mail) == already)
    }
}

struct SearchDateRangeTests {
    /// Wednesday 2026-11-18 15:30 UTC, in a calendar whose weeks start on Monday.
    private let now = ISO8601DateFormatter().date(from: "2026-11-18T15:30:00Z")!
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.firstWeekday = 2
        return calendar
    }

    private func range(_ start: String, _ end: String) throws -> SearchDateRange {
        let formatter = ISO8601DateFormatter()
        return SearchDateRange(
            start: try #require(formatter.date(from: start + "T00:00:00Z")),
            end: try #require(formatter.date(from: end + "T00:00:00Z"))
        )
    }

    @Test func presetsAreComputedFromNowAndTheCalendar() throws {
        #expect(SearchDatePreset.today.range(now: now, calendar: calendar) == (try range("2026-11-18", "2026-11-19")))
        #expect(SearchDatePreset.yesterday.range(now: now, calendar: calendar) == (try range("2026-11-17", "2026-11-18")))
        #expect(SearchDatePreset.thisWeek.range(now: now, calendar: calendar) == (try range("2026-11-16", "2026-11-23")))
        #expect(SearchDatePreset.lastWeek.range(now: now, calendar: calendar) == (try range("2026-11-09", "2026-11-16")))
        #expect(SearchDatePreset.last30Days.range(now: now, calendar: calendar) == (try range("2026-10-19", "2026-11-19")))
    }

    @Test func theWeekStartsWhereTheCalendarSays() throws {
        var sundayFirst = calendar
        sundayFirst.firstWeekday = 1
        #expect(SearchDatePreset.thisWeek.range(now: now, calendar: sundayFirst) == (try range("2026-11-15", "2026-11-22")))
    }

    @Test func presetsKeepTheirOrderAndNames() {
        #expect(SearchDatePreset.allCases.map(\.name) == ["Today", "Yesterday", "This week", "Last week", "Last 30 days"])
    }

    @Test func aRangeIsWrittenInWholeSecondsWidenedOutwards() {
        let range = SearchDateRange(start: Date(timeIntervalSince1970: 100.7), end: Date(timeIntervalSince1970: 200.2))
        #expect(range.filterValue == "100 201")
        #expect(range.filter == SearchFilter(type: .date, value: "100 201"))
    }

    @Test func onlyTwoNumbersMakeARange() {
        #expect(SearchDateRange(filterValue: "100 201")
            == SearchDateRange(start: Date(timeIntervalSince1970: 100), end: Date(timeIntervalSince1970: 201)))
        #expect(SearchDateRange(filterValue: "100") == nil)
        #expect(SearchDateRange(filterValue: "100 x") == nil)
        #expect(SearchDateRange(filterValue: "1 2 3") == nil)
    }
}
