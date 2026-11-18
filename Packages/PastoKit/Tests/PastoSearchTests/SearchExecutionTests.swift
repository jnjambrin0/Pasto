import Foundation
import PastoCore
import PastoRecognition
@testable import PastoSearch
import Testing

struct NewestHitsTests {
    private func id(_ rawValue: String) -> ItemID {
        ItemID(rawValue: rawValue)
    }

    @Test func keepsTheNewestUpToTheLimitNewestFirst() {
        var hits = NewestHits(limit: 3)
        for (name, second) in [("a", 1.0), ("b", 5), ("c", 3), ("d", 4), ("e", 2)] {
            hits.insert(id(name), date: Date(timeIntervalSince1970: second))
        }
        #expect(hits.ids == [id("b"), id("d"), id("c")])
    }

    @Test func tiesGoToTheGreaterIdentifierAndUndatedHitsLast() {
        var hits = NewestHits(limit: 4)
        let date = Date(timeIntervalSince1970: 1)
        hits.insert(id("undated"), date: nil)
        hits.insert(id("a"), date: date)
        hits.insert(id("b"), date: date)
        #expect(hits.ids == [id("b"), id("a"), id("undated")])
    }
}

struct SearchIndexItemTests {
    private let item = IndexableItem(
        id: ItemID(rawValue: "1"), type: .link, text: "https://example.com", timestamp: Date(timeIntervalSince1970: 9),
        applicationName: "Safari", deviceName: "Mac", pinboardID: ListID(rawValue: "P1")
    )

    @Test func anItemIsWrittenWithEverythingItIsFoundBy() {
        let indexed = SearchIndexItem(item)
        #expect(indexed.title == "Link")
        #expect(indexed.text == "https://example.com")
        #expect(indexed.modificationDate == Date(timeIntervalSince1970: 9))
        #expect(indexed.application == "Safari")
        #expect(indexed.type == "Link")
        #expect(indexed.device == "Mac")
        #expect(indexed.pinboard == "P1")
    }

    @Test func aNamedItemKeepsItsNameAndAnUnpinnedOneHasNoPinboard() {
        var named = item
        named.title = "Docs"
        named.pinboardID = nil
        #expect(SearchIndexItem(named).title == "Docs")
        #expect(SearchIndexItem(named).pinboard == "")
    }

    @Test func textIsCutAtFiveThousandCharactersRecognizedWordsIncluded() {
        var long = item
        long.text = String(repeating: "a", count: 4999)
        #expect(SearchIndexItem(long, recognizedText: "words").text == long.text.map { $0 + "\n" })

        var image = item
        image.text = nil
        #expect(SearchIndexItem(image, recognizedText: "Total 42").text == "Total 42")
        #expect(SearchIndexItem(image).text == nil)
    }
}

struct RecognizedTextTests {
    @Test func wordsAreWhatIsLeftBetweenSpacesAndPunctuation() {
        #expect(RecognizedText.words(in: "Total: 42,50\nme@example.com ") == ["Total", "42", "50", "me", "example", "com"])
        #expect(RecognizedText.words(in: " … ").isEmpty)
    }
}

@MainActor
@Suite(.timeLimit(.minutes(1)))
struct SearchSessionTests {
    private let fixture: SearchFixture
    private let session: SearchSession
    private let states = StateLog()

    @MainActor
    private final class StateLog {
        var states: [SearchSession.State] = []
    }

    init() throws {
        fixture = try SearchFixture()
        let service = SearchService(index: fixture.index, reader: StoreReader(stack: fixture.stack))
        session = SearchSession(service: service, sleep: fixture.sleeps.sleep)
        session.onStateChange = { [states] in states.states.append($0) }
    }

    /// Waits out the debounce of the last query, and the search it started, if any.
    private func settle() async {
        await session.debounce?.value
        await session.search?.value
    }

    @Test func aQueryIsSearchedForAfterTheDebounceAndItsResultsComeNewestFirst() async throws {
        let ids = try await fixture.recordTexts(3)
        await fixture.index.setHits([ids[0], ItemID(rawValue: "deleted meanwhile"), ids[2]])

        session.update(SearchQuery(text: "text"))
        #expect(session.state == .idle)
        await settle()

        #expect(fixture.sleeps.durations == [.milliseconds(120)])
        #expect(states.states == [.searching, .results([ids[2], ids[0]])])
    }

    @Test func noMatchesReadAsNothingFound() async throws {
        session.update(SearchQuery(text: "missing"))
        await settle()
        #expect(session.state == .nothingFound)
    }

    @Test func aNewQueryAbandonsThePreviousOne() async throws {
        let ids = try await fixture.recordTexts(1)
        await fixture.index.setHits(ids)

        session.update(SearchQuery(text: "fir"))
        session.update(SearchQuery(text: "first"))
        await settle()

        #expect(await fixture.index.queryStrings.count == 1)
        #expect(await fixture.index.queryStrings.first?.contains("first*") == true)
        #expect(states.states == [.searching, .results(ids)])
    }

    @Test func theSameQueryIsNotSearchedForTwice() async throws {
        session.update(SearchQuery(text: "same"))
        await settle()
        session.update(SearchQuery(text: "same"))
        await settle()
        #expect(await fixture.index.queryStrings.count == 1)
    }

    @Test func aQueryTakenBackWithinTheDebounceChangesNothing() async throws {
        session.update(SearchQuery(text: "ab"))
        await settle()

        session.update(SearchQuery(text: "abc"))
        session.update(SearchQuery(text: "ab"))
        await settle()
        session.update(SearchQuery())
        session.update(SearchQuery(text: "ab"))
        await settle()

        #expect(await fixture.index.queryStrings.count == 1)
        #expect(states.states == [.searching, .nothingFound])
    }

    /// Lets a test say when a search's time limit is up.
    private final class TimeLimitGate: Sendable {
        private let feed = AsyncStream.makeStream(of: Void.self)

        func expire() {
            feed.continuation.yield()
        }

        var wait: @Sendable (Duration) async throws -> Void {
            { [stream = feed.stream] _ in
                for await _ in stream { return }
                throw CancellationError()
            }
        }
    }

    @Test func aSearchLeftUnansweredShowsNothingFoundAndTheNextKeyTriesAgain() async throws {
        let ids = try await fixture.recordTexts(1)
        await fixture.index.setHits(ids)
        await fixture.index.setUnresponsive(true)
        let gate = TimeLimitGate()
        let service = SearchService(index: fixture.index, reader: StoreReader(stack: fixture.stack))
        let session = SearchSession(service: service, sleep: fixture.sleeps.sleep, waitForTimeLimit: gate.wait)

        session.update(SearchQuery(text: "first"))
        await session.debounce?.value
        #expect(session.state == .searching)
        gate.expire()
        await session.search?.value
        #expect(session.state == .nothingFound)

        // Spotlight answers again; the same query, typed again, is searched for again.
        await fixture.index.setUnresponsive(false)
        session.update(SearchQuery(text: "first"))
        await session.debounce?.value
        await session.search?.value
        #expect(session.state == .results(ids))
        #expect(await fixture.index.queryStrings.count == 2)
    }

    @Test func emptyingTheQueryGoesBackToIdleWithoutSearching() async throws {
        session.update(SearchQuery(text: "something"))
        await settle()
        session.update(SearchQuery(components: [.token("  ")]))
        await settle()

        #expect(session.state == .idle)
        #expect(await fixture.index.queryStrings.count == 1)
    }
}
