import Foundation
import PastoCore
import PastoSearch
import PastoUI
import Testing
@testable import PastoMainPanel

@Suite struct SuggestionSelectionTests {
    @Test func startsWithNothingSelected() {
        #expect(SuggestionSelection(rowCount: 3).index == nil)
    }

    @Test func theFirstMoveEntersFromTheEndItComesFrom() {
        var down = SuggestionSelection(rowCount: 3)
        down.move(by: 1)
        #expect(down.index == 0)

        var up = SuggestionSelection(rowCount: 3)
        up.move(by: -1)
        #expect(up.index == 2)
    }

    @Test func movesStopAtTheEndsWithoutWrapping() {
        var selection = SuggestionSelection(rowCount: 3)
        selection.move(by: 1)
        selection.move(by: 5)
        #expect(selection.index == 2)
        selection.move(by: 1)
        #expect(selection.index == 2)
        selection.move(by: -3)
        #expect(selection.index == 0)
        selection.move(by: -1)
        #expect(selection.index == 0)
    }

    @Test func anEmptyMenuHasNothingToSelect() {
        var selection = SuggestionSelection(rowCount: 0)
        selection.move(by: 1)
        #expect(selection.index == nil)
    }

    @Test func thePointerSelectsAndClears() {
        var selection = SuggestionSelection(rowCount: 3)
        selection.select(1)
        #expect(selection.index == 1)
        selection.select(7)
        #expect(selection.index == nil)
        selection.select(2)
        selection.select(nil)
        #expect(selection.index == nil)
    }

    @Test func navigationKeysMoveTheSelection() {
        let selection = SuggestionSelection(rowCount: 12)
        #expect(selection.action(forKeyCode: KeyCode.downArrow) == .move(by: 1))
        #expect(selection.action(forKeyCode: KeyCode.upArrow) == .move(by: -1))
        #expect(selection.action(forKeyCode: KeyCode.pageDown) == .move(by: 5))
        #expect(selection.action(forKeyCode: KeyCode.pageUp) == .move(by: -5))
        #expect(selection.action(forKeyCode: KeyCode.end) == .move(by: 12))
        #expect(selection.action(forKeyCode: KeyCode.home) == .move(by: -12))
        #expect(selection.action(forKeyCode: KeyCode.escape) == .dismiss)
    }

    /// Return, Tab and → only accept a selected row; without one they belong to the field.
    @Test func acceptingNeedsASelectedRow() {
        var selection = SuggestionSelection(rowCount: 3)
        for key in [KeyCode.returnKey, KeyCode.tab, KeyCode.rightArrow] {
            #expect(selection.action(forKeyCode: key) == .passThrough)
        }
        selection.move(by: 1)
        for key in [KeyCode.returnKey, KeyCode.tab, KeyCode.rightArrow] {
            #expect(selection.action(forKeyCode: key) == .accept)
        }
    }

    @Test func otherKeysGoOnToTheField() {
        var selection = SuggestionSelection(rowCount: 3)
        selection.move(by: 1)
        for key in [KeyCode.space, KeyCode.leftArrow, KeyCode.delete] {
            #expect(selection.action(forKeyCode: key) == .passThrough)
        }
    }
}

@Suite struct SearchEscapeTests {
    @Test func inTheFieldEscapeGoesDownOneRungAtATime() {
        #expect(SearchEscape.action(focus: .field, isSuggestionsMenuOpen: true, isQueryEmpty: false) == .closeSuggestions)
        #expect(SearchEscape.action(focus: .field, isSuggestionsMenuOpen: false, isQueryEmpty: false) == .clearQuery)
        #expect(SearchEscape.action(focus: .field, isSuggestionsMenuOpen: false, isQueryEmpty: true) == .dismissSearch)
    }

    @Test func overTheResultsEscapeLeavesTheSearchAndThenClosesThePanel() {
        #expect(SearchEscape.action(focus: .strip, isSuggestionsMenuOpen: false, isQueryEmpty: false) == .dismissSearch)
        #expect(SearchEscape.action(focus: .strip, isSuggestionsMenuOpen: false, isQueryEmpty: true) == .closePanel)
    }
}

@Suite struct FilterBrowserTests {
    private func suggestions(_ type: SearchFilterType, _ count: Int) -> [SearchSuggestion] {
        (0..<count).map { SearchSuggestion(filter: SearchFilter(type: type, value: "\(type.rawValue)\($0)"), title: "\($0)") }
    }

    private func sections(
        _ available: [SearchFilterType: [SearchSuggestion]],
        query: SearchQuery = SearchQuery(),
        hidesApplied: Bool = false,
        expanded: Set<SearchFilterType> = []
    ) -> [FilterBrowserSection] {
        FilterBrowserContent.sections(available: available, query: query, hidesApplied: hidesApplied, expanded: expanded)
    }

    @Test func sectionsFollowAFixedOrderAndEmptyOnesAreLeftOut() {
        let shown = sections([
            .device: suggestions(.device, 1),
            .date: suggestions(.date, 5),
            .app: [],
            .type: suggestions(.type, 6),
            .pinboard: suggestions(.pinboard, 2),
            .title: suggestions(.title, 1),
        ])
        #expect(shown.map(\.type) == [.type, .pinboard, .date, .device])
    }

    @Test func aSectionOfTenShowsEverythingWithoutAButton() {
        let section = sections([.app: suggestions(.app, 10)])[0]
        #expect(section.entries.count == 10)
        #expect(!section.entries.contains(.disclosure(.app, isExpanded: false)))
    }

    @Test func aSectionOfElevenStartsCollapsedToEight() {
        let available = [SearchFilterType.app: suggestions(.app, 11)]
        let collapsed = sections(available)[0]
        #expect(collapsed.entries.count == 9)
        #expect(collapsed.entries.last == .disclosure(.app, isExpanded: false))

        let expanded = sections(available, expanded: [.app])[0]
        #expect(expanded.entries.count == 12)
        #expect(expanded.entries.last == .disclosure(.app, isExpanded: true))
    }

    @Test func appliedFiltersAreMarkedOrHidden() {
        let available = [SearchFilterType.app: suggestions(.app, 3)]
        let applied = available[.app]![1]
        let query = SearchQuery(components: [.filter(applied.filter)])

        let marked = sections(available, query: query)[0]
        #expect(marked.entries == [
            .filter(available[.app]![0], isSelected: false),
            .filter(applied, isSelected: true),
            .filter(available[.app]![2], isSelected: false),
        ])

        let hidden = sections(available, query: query, hidesApplied: true)[0]
        #expect(hidden.entries.count == 2)
        #expect(!hidden.entries.contains(.filter(applied, isSelected: true)))
    }

    @Test func choosingAFilterAddsItAtTheEndOrRemovesEveryCopy() {
        let mail = SearchFilter(type: .app, value: "Mail")
        let notes = SearchFilter(type: .app, value: "Notes")
        let query = SearchQuery(components: [.filter(mail), .token("x")])

        let added = FilterBrowserContent.toggling(notes, in: query)
        #expect(added.components == [.filter(mail), .token("x"), .filter(notes)])

        let removed = FilterBrowserContent.toggling(mail, in: SearchQuery(components: [.filter(mail), .token("x"), .filter(mail)]))
        #expect(removed.components == [.token("x")])
    }

    // Two sections: 7 entries (rows 0–2, 3–5, 6) and 4 entries (rows 7–9, 10).
    private func move(_ index: Int?, _ direction: FilterBrowserNavigation.Direction, sizes: [Int] = [7, 4]) -> Int? {
        FilterBrowserNavigation.index(from: index, moving: direction, sectionSizes: sizes)
    }

    @Test func theFirstMoveHighlightsTheFirstEntry() {
        #expect(move(nil, .up) == 0)
        #expect(move(nil, .right) == 0)
        #expect(move(nil, .down, sizes: []) == nil)
    }

    @Test func leftAndRightWrapAroundTheWholeBrowser() {
        #expect(move(6, .right) == 7)
        #expect(move(10, .right) == 0)
        #expect(move(0, .left) == 10)
        #expect(move(7, .left) == 6)
    }

    @Test func upAndDownStayInTheColumnWithinASection() {
        #expect(move(1, .down) == 4)
        #expect(move(4, .up) == 1)
        // The last row has one entry: from the other columns, down lands on it.
        #expect(move(4, .down) == 6)
        #expect(move(3, .down) == 6)
    }

    @Test func downFromTheLastRowEntersTheNextSection() {
        #expect(move(6, .down) == 7)
        // From the last section, around to the first entry.
        #expect(move(10, .down) == 0)
        // The column is kept as far as the next section's first row allows.
        #expect(move(5, .down, sizes: [6, 2]) == 7)
    }

    @Test func upFromTheFirstRowEntersTheLastRowOfThePreviousSection() {
        #expect(move(7, .up) == 6)
        #expect(move(9, .up) == 6)
        #expect(move(8, .up, sizes: [6, 4]) == 5)
        // From the first section, around to the last entry.
        #expect(move(1, .up) == 10)
    }
}

@Suite struct SearchFilterDisplayTests {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        return calendar
    }

    /// 17 November 2026, 12:00 UTC.
    private let now = Date(timeIntervalSince1970: 1_794_916_800)

    private func title(_ filter: SearchFilter, now: Date? = nil) -> String {
        SearchFilterDisplay.title(
            for: filter,
            pinboardName: { $0.rawValue == "p1" ? "Recipes" : nil },
            now: now ?? self.now,
            calendar: calendar
        )
    }

    @Test func mostFiltersReadAsTheirValue() {
        #expect(title(SearchFilter(type: .app, value: "Mail")) == "Mail")
        #expect(title(SearchFilter(type: .type, value: "Link")) == "Link")
        #expect(title(SearchFilter(type: .device, value: "MacBook")) == "MacBook")
    }

    @Test func aPinboardReadsAsItsNameWhileItExists() {
        #expect(title(SearchFilter(type: .pinboard, value: "p1")) == "Recipes")
        #expect(title(SearchFilter(type: .pinboard, value: "gone")) == "gone")
    }

    /// A date filter is called by its preset only while its range is the preset's as of now.
    @Test func aDateReadsAsItsPresetOnlyWhileItMatches() throws {
        let today = try #require(SearchDatePreset.today.range(now: now, calendar: calendar)).filter
        #expect(title(today) == "Today")
        // A day later the same range is yesterday's.
        #expect(title(today, now: now.addingTimeInterval(86_400)) == "Yesterday")
        // Two days later it is no preset's: it reads as its dates.
        #expect(title(today, now: now.addingTimeInterval(2 * 86_400)) == "Nov 17, 2026 – Nov 18, 2026")
    }

    @Test func anUnreadableDateReadsAsItsValue() {
        #expect(title(SearchFilter(type: .date, value: "soon")) == "soon")
    }

    @Test func iconsFollowTheFiltersTypeAndValue() {
        func icon(_ type: SearchFilterType, _ value: String) -> SearchFilterIcon {
            SearchFilterDisplay.icon(
                for: SearchFilter(type: type, value: value),
                applicationIcon: { $0 == "Notes" ? Data([1]) : nil },
                deviceType: { ["Desk": .mac, "Phone": .iPhone, "Tablet": .iPad][$0] },
                pinboardColor: { $0.rawValue == "p1" ? .green : nil }
            )
        }
        #expect(icon(.app, "Notes") == .image(Data([1])))
        #expect(icon(.app, "Gone") == .symbol("app.dashed"))
        #expect(icon(.device, "Desk") == .symbol("macbook"))
        #expect(icon(.device, "Phone") == .symbol("iphone"))
        #expect(icon(.device, "Tablet") == .symbol("ipad"))
        #expect(icon(.device, "Gone") == .symbol("macbook.and.iphone"))
        #expect(icon(.type, "Link") == .symbol("link"))
        #expect(icon(.type, "Image") == .symbol("photo"))
        #expect(icon(.type, "Color") == .symbol("paintpalette"))
        #expect(icon(.type, "Text") == .symbol("text.alignleft"))
        #expect(icon(.type, "File") == .symbol("doc"))
        #expect(icon(.type, "Unknown") == .symbol("questionmark.app"))
        #expect(icon(.type, "Sound") == .symbol("exclamationmark.triangle.fill"))
        #expect(icon(.date, "0 1") == .symbol("calendar"))
        #expect(icon(.title, "x") == .none)
        #expect(icon(.pinboard, "p1") == .pinboardDot(.green))
        #expect(icon(.pinboard, "gone") == .symbol("circle.fill"))
    }
}
