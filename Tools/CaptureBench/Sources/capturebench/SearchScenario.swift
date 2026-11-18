import CoreSpotlight
import Foundation
import PastoCore
@_spi(Benchmarks) import PastoSearch

/// Searching a large index: a private Core Spotlight index of the benchmark's own (its own bundle
/// identifier and index name), filled with a year of synthetic history.
enum SearchScenario {
    static let indexName = "jnjambrino.Pasto.CaptureBench.search"

    /// Words of the synthetic history. "the" is in about 60 % of the items; "zyxwq" in a handful.
    static let frequentWord = "the"
    static let rareWord = "zyxwq"

    /// Empties the index and fills it with `total` items spread over the year before now, newest
    /// last; with `from`, adds the items from that position on to what is there.
    static func fill(total: Int, from first: Int = 0, pause: Duration = .zero) async throws {
        let index = SpotlightSearchIndex(indexName: indexName)
        guard index.isAvailable else { throw BenchError("Core Spotlight indexing is not available") }
        if first == 0 {
            print("emptying the index")
            try await index.deleteAll()
            print("emptied")
        }
        var generator = SplitMix64(seed: 2026)
        let vocabulary = makeVocabulary(using: &generator)
        let now = Date()
        let year: TimeInterval = 365 * 24 * 3600
        let apps = ["Safari", "Mail", "Xcode", "Notes", "Slack", "Terminal", "Finder", "Messages", "Pages", "TextEdit"]
        let batch = 1000
        let start = ContinuousClock.now
        for batchStart in stride(from: first, to: total, by: batch) {
            let items = (batchStart..<min(batchStart + batch, total)).map { position -> SearchIndexItem in
                var local = SplitMix64(seed: UInt64(position) &* 0x9E37_79B9)
                // Evenly spread over the year: item `total - 1` is the newest whatever `total` is.
                let age = year * (1 - Double(position) / Double(total))
                let roll = local.next() % 100
                let type: ItemType = roll < 70 ? .text : roll < 85 ? .link : roll < 95 ? .image : .files
                var words = (0..<16).map { _ in vocabulary[Int(local.next() % UInt64(vocabulary.count))] }
                if local.next() % 100 < 60 { words.append(frequentWord) }
                if position % 50_000 == 7 { words.append(rareWord) }
                let item = IndexableItem(
                    id: ItemID(rawValue: String(format: "bench-%08d", position)),
                    type: type,
                    text: type == .image ? nil : words.joined(separator: " "),
                    timestamp: now.addingTimeInterval(-age),
                    applicationName: apps[Int(local.next() % UInt64(apps.count))],
                    deviceName: "Bench Mac"
                )
                return SearchIndexItem(item)
            }
            // A batch that gets no answer in a minute is reported rather than waited for forever.
            let written = await withTaskGroup(of: Bool.self) { group in
                group.addTask { (try? await index.index(items, isUpdate: false)) != nil }
                group.addTask { try? await Task.sleep(for: .seconds(60)); return false }
                let first = await group.next() ?? false
                group.cancelAll()
                return first
            }
            guard written else {
                print("no answer for the batch at \(batchStart) after 60 s")
                throw BenchError("indexing stalled at \(batchStart)")
            }
            if pause > .zero { try await Task.sleep(for: pause) }
            if (batchStart / batch) % 10 == 0 {
                print("indexed \(batchStart + items.count)/\(total) in \(Int((ContinuousClock.now - start).milliseconds / 1000)) s")
            }
        }
        print("indexed \(total) in \(Int((ContinuousClock.now - start).milliseconds / 1000)) s; waiting until searchable")
        // Core Spotlight makes items searchable a little after it accepts them.
        let probe = SearchQueryString.make(for: SearchQuery(text: rareWord))!
        for _ in 0..<120 {
            let hits = try await index.newestItemIDs(matching: probe, limit: 100)
            if hits.count >= max(1, total / 50_000) { break }
            try await Task.sleep(for: .seconds(1))
        }
        ResultLine(scenario: "search-fill", values: [
            "documents": Double(total),
            "fill_s": (ContinuousClock.now - start).milliseconds / 1000,
        ]).print()
    }

    struct Probe {
        let name: String
        let query: SearchQuery
    }

    static let probes: [Probe] = [
        Probe(name: "one_letter", query: SearchQuery(text: "a")),
        Probe(name: "frequent_word", query: SearchQuery(text: frequentWord)),
        Probe(name: "rare_word", query: SearchQuery(text: rareWord)),
        Probe(name: "type_filter", query: SearchQuery(components: [.filter(SearchFilter(type: .type, value: "Text")), .token("a")])),
        Probe(name: "app_filter", query: SearchQuery(components: [.filter(SearchFilter(type: .app, value: "Safari")), .token(frequentWord)])),
        Probe(name: "filter_only", query: SearchQuery(components: [.filter(SearchFilter(type: .type, value: "Link"))])),
    ]

    /// Runs every probe `repeats` times and reports the median and the worst time to results, and
    /// how fast a search under way stops when a newer one replaces it.
    static func query(documents: Int, repeats: Int) async throws {
        let index = SpotlightSearchIndex(indexName: indexName)
        var values: [String: Double] = ["documents": Double(documents)]
        for probe in probes {
            let queryString = SearchQueryString.make(for: probe.query)!
            var times: [Double] = []
            var count = 0
            for _ in 0..<repeats {
                let start = ContinuousClock.now
                let hits = try await index.newestItemIDs(matching: queryString, limit: SearchService.resultLimit)
                times.append((ContinuousClock.now - start).milliseconds)
                count = hits.count
            }
            times.sort()
            values["\(probe.name)_median_ms"] = times[times.count / 2]
            values["\(probe.name)_max_ms"] = times.last
            values["\(probe.name)_hits"] = Double(count)
        }

        // What one query costs by how far back it reaches: the basis for searching recent time first.
        let now = Date()
        for days in [1, 7, 30, 365] {
            let range = SearchDateRange(start: now.addingTimeInterval(-Double(days) * 86_400), end: now.addingTimeInterval(86_400))
            for (name, text) in [("one_letter", "a"), ("frequent_word", frequentWord)] {
                let query = SearchQuery(components: [.filter(range.filter), .token(text)])
                let queryString = SearchQueryString.make(for: query)!
                var times: [Double] = []
                var count = 0
                for _ in 0..<repeats {
                    let start = ContinuousClock.now
                    count = try await index.newestItemIDs(matching: queryString, limit: SearchService.resultLimit).count
                    times.append((ContinuousClock.now - start).milliseconds)
                }
                times.sort()
                values["window_\(days)d_\(name)_median_ms"] = times[times.count / 2]
                values["window_\(days)d_\(name)_hits"] = Double(count)
            }
        }

        // A single lower bound, as the search's windows are written: cost by reach.
        for days in [1, 7, 30, 365] {
            let since = now.addingTimeInterval(-Double(days) * 86_400).formatted(.iso8601)
            let probes = [("rare", SearchQuery(text: rareWord)), ("one_letter", SearchQuery(text: "a")),
                          ("app_filter", SearchQuery(components: [.filter(SearchFilter(type: .app, value: "Safari")), .token(frequentWord)]))]
            for (name, query) in probes {
                let queryString = "(\(SearchQueryString.make(for: query)!)) && contentModificationDate >= $time.iso(\(since))"
                var times: [Double] = []
                var count = 0
                for _ in 0..<repeats {
                    let start = ContinuousClock.now
                    count = try await rawCount(queryString)
                    times.append((ContinuousClock.now - start).milliseconds)
                }
                times.sort()
                values["since_\(days)d_\(name)_median_ms"] = times[times.count / 2]
                values["since_\(days)d_\(name)_hits"] = Double(count)
            }
        }

        // A query under way is cancelled 30 ms in, as a newer keystroke does.
        let queryString = SearchQueryString.make(for: SearchQuery(text: "a"))!
        var stopTimes: [Double] = []
        for _ in 0..<repeats {
            let task = Task { try await index.newestItemIDs(matching: queryString, limit: SearchService.resultLimit) }
            try await Task.sleep(for: .milliseconds(30))
            let cancelledAt = ContinuousClock.now
            task.cancel()
            _ = await task.result
            stopTimes.append((ContinuousClock.now - cancelledAt).milliseconds)
        }
        stopTimes.sort()
        values["cancel_stop_median_ms"] = stopTimes[stopTimes.count / 2]
        values["cancel_stop_max_ms"] = stopTimes.last
        ResultLine(scenario: "search", values: values).print()
    }

    /// One query on its own, as Spotlight answers it: how many hits, delivered in batches.
    static func rawCount(_ queryString: String) async throws -> Int {
        let context = CSSearchQueryContext()
        context.fetchAttributes = ["contentModificationDate"]
        let query = CSSearchQuery(queryString: queryString, queryContext: context)
        let counter = OSAllocatedUnfairLockBox(0)
        query.foundItemsHandler = { items in counter.set(counter.value + items.count) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            query.completionHandler = { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
            query.start()
        }
        return counter.value
    }

    /// How many items the index finds for `pastoType == "*"`, and how long it takes.
    static func count() async throws {
        let start = ContinuousClock.now
        let query = CSSearchQuery(queryString: "pastoType == \"*\"", queryContext: nil)
        var count = 0
        for try await _ in query.results { count += 1 }
        print("searchable items: \(count) (\(Int((ContinuousClock.now - start).milliseconds)) ms)")
    }

    static func clean() async throws {
        try await SpotlightSearchIndex(indexName: indexName).deleteAll()
        // Every index of this executable, whatever its name.
        try await CSSearchableIndex.default().deleteAllSearchableItems()
        print("Deleted the benchmark's search index")
    }

    private static func makeVocabulary(using generator: inout SplitMix64) -> [String] {
        let syllables = ["ka", "re", "mi", "to", "sa", "lu", "ne", "po", "di", "fa", "gor", "ben", "tri", "al", "an", "ex", "or", "in", "um", "es"]
        return (0..<4000).map { _ in
            let count = 2 + Int(generator.next() % 3)
            return (0..<count).map { _ in syllables[Int(generator.next() % UInt64(syllables.count))] }.joined()
        }
    }
}

/// A seeded generator, so that every run builds the same history.
struct SplitMix64: RandomNumberGenerator {
    private var state: UInt64

    init(seed: UInt64) {
        state = seed
    }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var value = state
        value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
        value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
        return value ^ (value >> 31)
    }
}
