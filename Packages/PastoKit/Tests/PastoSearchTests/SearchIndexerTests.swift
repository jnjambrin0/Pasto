import Foundation
import os
import PastoCore
import PastoFoundation
import PastoRecognition
@testable import PastoSearch
import Testing

struct SearchIndexerStartupTests {
    private func state(schema: Int = IndexingState.currentSchemaVersion, total: Int, indexed: Int) -> IndexingState {
        IndexingState(schemaVersion: schema, totalItems: total, indexedItems: indexed, oldestTimestamp: nil, invalidItems: 0)
    }

    @Test func theSavedStateDecidesWhatAStartDoes() {
        let done = state(total: 10, indexed: 10)
        #expect(SearchIndexerStartup.plan(state: nil, indexedStoreID: "A", storeID: "A") == .rebuild(.noSavedState))
        #expect(SearchIndexerStartup.plan(state: done, indexedStoreID: "A", storeID: "B") == .rebuild(.storeChanged))
        #expect(SearchIndexerStartup.plan(state: state(schema: 0, total: 10, indexed: 10), indexedStoreID: "A", storeID: "A")
            == .rebuild(.schemaChanged))
        // An index written before the history left the system's search is rebuilt.
        #expect(SearchIndexerStartup.plan(state: state(schema: 1, total: 10, indexed: 10), indexedStoreID: "A", storeID: "A")
            == .rebuild(.schemaChanged))
        #expect(SearchIndexerStartup.plan(state: state(total: 10, indexed: 4), indexedStoreID: "A", storeID: "A")
            == .resume(state(total: 10, indexed: 4)))
        #expect(SearchIndexerStartup.plan(state: done, indexedStoreID: "A", storeID: "A") == .probe(done))
        #expect(SearchIndexerStartup.plan(state: state(total: 0, indexed: 0), indexedStoreID: "A", storeID: "A") == .upToDate)
        // An unknown store on either side is not a change of store.
        #expect(SearchIndexerStartup.plan(state: done, indexedStoreID: nil, storeID: "B") == .probe(done))
    }
}

struct RecognitionQueueTests {
    private func ids(_ rawValues: String...) -> [ItemID] {
        rawValues.map(ItemID.init)
    }

    @Test func itemsAreReadFirstInFirstOutAndQueuedOnce() {
        var queue = RecognitionQueue(ids("a", "b"))
        queue.append(ids("b", "c", "a", "c"))
        #expect(queue.ids == ids("a", "b", "c"))

        #expect(queue.popFirst() == ItemID(rawValue: "a"))
        // Once taken off, an item can be queued again.
        queue.append(ids("a"))
        #expect(queue.ids == ids("b", "c", "a"))
    }

    @Test func anInterruptedItemGoesBackToTheFrontAndRemovedOnesLeave() throws {
        var queue = RecognitionQueue(ids("a", "b", "c"))
        let first = queue.popFirst()
        queue.putBack(try #require(first))
        queue.putBack(ItemID(rawValue: "b"))
        #expect(queue.ids == ids("a", "b", "c"))

        queue.remove(Set(ids("b", "missing")))
        #expect(queue.ids == ids("a", "c"))
        queue.append(ids("b"))
        #expect(queue.ids == ids("a", "c", "b"))
        queue.remove(Set(ids("a", "b", "c")))
        #expect(queue.isEmpty)
        #expect(queue.popFirst() == nil)
    }
}

struct SearchIndexChangesTests {
    private func transaction(_ changes: (String, HistoryTransaction.ItemChange.Kind)...) -> HistoryTransaction {
        HistoryTransaction(author: .capture, changes: changes.map { .init(id: ItemID(rawValue: $0.0), kind: $0.1) })
    }

    private func ids(_ rawValues: String...) -> Set<ItemID> {
        Set(rawValues.map(ItemID.init))
    }

    @Test func everyItemEndsInOneSet() {
        let changes = SearchIndexChanges([
            transaction(("new", .inserted), ("old", .updated), ("gone", .updated)),
            transaction(("new", .updated), ("gone", .deleted), ("back", .deleted)),
            transaction(("back", .inserted)),
        ])
        #expect(changes.inserted == ids("new", "back"))
        #expect(changes.updated == ids("old"))
        #expect(changes.deleted == ids("gone"))
    }

    @Test func laterChangesOverrideEarlierOnes() {
        var changes = SearchIndexChanges([transaction(("a", .inserted), ("b", .updated))])
        changes.merge(SearchIndexChanges([transaction(("a", .deleted), ("b", .updated), ("c", .inserted))]))
        #expect(changes.inserted == ids("c"))
        #expect(changes.updated == ids("b"))
        #expect(changes.deleted == ids("a"))
    }
}

@Suite(.timeLimit(.minutes(1)))
struct SearchIndexerTests {
    private struct Broken: Error {}
    private let unavailable = SearchIndexError.transientlyUnavailable(code: -1000)

    // MARK: - Indexing the whole store

    @Test func theFirstStartIndexesEverythingInBatchesAndSavesItsProgress() async throws {
        let fixture = try SearchFixture()
        let ids = try await fixture.recordTexts(250)
        await fixture.makeIndexer().start()

        #expect(await fixture.index.operations == [
            .deleteAll,
            .index(count: 100, isUpdate: false), .index(count: 100, isUpdate: false), .index(count: 50, isUpdate: false),
        ])
        #expect(await Set(fixture.index.items.keys) == Set(ids))
        #expect(fixture.savedState == IndexingState(
            schemaVersion: IndexingState.currentSchemaVersion,
            totalItems: 250, indexedItems: 250, oldestTimestamp: Date(timeIntervalSinceReferenceDate: 1), invalidItems: 0
        ))
    }

    @Test func aStartIsNotRepeatedWhileRunning() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(1)
        let indexer = fixture.makeIndexer()
        await indexer.start()
        await indexer.start()
        #expect(await fixture.index.operations == [.deleteAll, .index(count: 1, isUpdate: false)])
    }

    @Test func nothingIsIndexedWhereIndexingIsUnavailable() async throws {
        let fixture = try SearchFixture(index: FakeSearchIndex(isAvailable: false))
        _ = try await fixture.recordTexts(1)
        await fixture.makeIndexer().start()
        #expect(await fixture.index.operations.isEmpty)
        #expect(fixture.savedState == nil)
    }

    @Test func anInterruptedIndexingIsResumedWhereItStopped() async throws {
        let fixture = try SearchFixture()
        let ids = try await fixture.recordTexts(250)
        // Emptying the index and the first batch go through; the second batch fails for good.
        await fixture.index.failWrites(after: 2, with: [Broken()])
        await fixture.makeIndexer().start()
        #expect(fixture.savedState?.indexedItems == 100)
        #expect(fixture.savedState?.oldestTimestamp == Date(timeIntervalSinceReferenceDate: 151))

        await fixture.index.forgetOperations()
        await fixture.makeIndexer().start()
        #expect(await fixture.index.operations == [.index(count: 100, isUpdate: false), .index(count: 50, isUpdate: false)])
        #expect(await Set(fixture.index.items.keys) == Set(ids))
        #expect(fixture.savedState?.indexedItems == 250)
        #expect(fixture.savedState?.totalItems == 250)
    }

    @Test func aFinishedIndexIsOnlyProbed() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(3)
        await fixture.makeIndexer().start()
        await fixture.index.forgetOperations()

        await fixture.makeIndexer().start()
        #expect(await fixture.index.operations.isEmpty)
    }

    @Test func aLostIndexIsRebuilt() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(3)
        await fixture.makeIndexer().start()
        await fixture.index.lose()

        await fixture.makeIndexer().start()
        #expect(await fixture.index.operations == [.deleteAll, .index(count: 3, isUpdate: false)])
    }

    @Test func anotherSchemaVersionForcesARebuild() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(3)
        await fixture.makeIndexer().start()
        await fixture.index.forgetOperations()
        var outdated = try #require(fixture.savedState)
        outdated.schemaVersion -= 1
        fixture.config.set(JSONConfigValue(outdated), for: .searchIndexingState)

        await fixture.makeIndexer().start()
        #expect(await fixture.index.operations == [.deleteAll, .index(count: 3, isUpdate: false)])
        #expect(fixture.savedState?.schemaVersion == IndexingState.currentSchemaVersion)
    }

    // MARK: - Retries

    @Test func aTransientFailureIsRetriedAfterOneAndTwoSeconds() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(1)
        await fixture.index.failWrites(with: [unavailable, unavailable])
        await fixture.makeIndexer().start()

        #expect(fixture.sleeps.durations == [.seconds(1), .seconds(2)])
        #expect(await fixture.index.operations == [.deleteAll, .index(count: 1, isUpdate: false)])
    }

    @Test func theThirdTransientFailureInARowIsGivenUpOn() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(1)
        await fixture.index.failWrites(with: [unavailable, unavailable, unavailable])
        await fixture.makeIndexer().start()

        #expect(fixture.sleeps.durations == [.seconds(1), .seconds(2)])
        #expect(await fixture.index.operations.isEmpty)
    }

    @Test func anyOtherFailureIsNotRetried() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(1)
        await fixture.index.failWrites(with: [Broken()])
        await fixture.makeIndexer().start()

        #expect(fixture.sleeps.durations.isEmpty)
        #expect(await fixture.index.operations.isEmpty)
    }

    // MARK: - Following the store

    @Test func storeChangesReachTheIndex() async throws {
        let fixture = try SearchFixture()
        let ids = try await fixture.recordTexts(2)
        let indexer = fixture.makeIndexer()
        await indexer.start()
        await fixture.index.forgetOperations()

        let added = try await fixture.writer.perform(author: .capture) { try $0.record(.text("added", at: 10)).id }
        try await fixture.writer.perform(author: .user) { context in
            try context.setTitle("Renamed", of: ids[0])
            try context.delete([ids[1]])
        }
        await indexer.storeDidChange([
            HistoryTransaction(author: .capture, changes: [.init(id: added, kind: .inserted)]),
            HistoryTransaction(author: .user, changes: [.init(id: ids[0], kind: .updated), .init(id: ids[1], kind: .deleted)]),
        ])

        #expect(await fixture.index.operations == [
            .delete([ids[1]]), .index(count: 1, isUpdate: false), .index(count: 1, isUpdate: true),
        ])
        #expect(await fixture.index.items[ids[0]]?.title == "Renamed")
        #expect(await fixture.index.items[added]?.text == "added")
        #expect(await fixture.index.items[ids[1]] == nil)
    }

    @Test func changesThatCouldNotBeAppliedAreAppliedWithTheNextOnes() async throws {
        let fixture = try SearchFixture()
        let ids = try await fixture.recordTexts(2)
        let indexer = fixture.makeIndexer()
        await indexer.start()
        await fixture.index.forgetOperations()

        await fixture.index.failWrites(with: [Broken()])
        await indexer.storeDidChange([HistoryTransaction(author: .user, changes: [.init(id: ids[0], kind: .updated)])])
        #expect(await fixture.index.operations.isEmpty)

        await indexer.storeDidChange([HistoryTransaction(author: .user, changes: [.init(id: ids[1], kind: .updated)])])
        #expect(await fixture.index.operations == [.index(count: 2, isUpdate: true)])
    }

    @Test func changesAreReindexedInBatchesAndWhatTheStoreNoLongerHasLeavesTheIndex() async throws {
        let fixture = try SearchFixture()
        let indexer = fixture.makeIndexer()
        await indexer.start()
        let ids = try await fixture.recordTexts(150)
        await fixture.index.forgetOperations()

        let gone = ItemID(rawValue: "gone")
        await indexer.storeDidChange([
            HistoryTransaction(author: .capture, changes: ids.map { .init(id: $0, kind: .inserted) }),
            HistoryTransaction(author: .user, changes: [.init(id: gone, kind: .updated)]),
        ])

        #expect(await fixture.index.operations == [
            .index(count: 100, isUpdate: false), .index(count: 50, isUpdate: false), .delete([gone]),
        ])
        #expect(await Set(fixture.index.items.keys) == Set(ids))
    }

    @Test func anIndexAboutToBeBuiltFromScratchSkipsTheHistoryBeforeFollowingIt() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(3)
        let firstLaunch = CountingDataSource(fixture.dataSource)
        await fixture.makeIndexer(dataSource: firstLaunch).follow(fixture.tailer)
        #expect(firstLaunch.skipCount == 1)

        // Once the index is built, the next launch takes the history up where it was.
        await fixture.makeIndexer().start()
        let nextLaunch = CountingDataSource(fixture.dataSource)
        await fixture.makeIndexer(dataSource: nextLaunch).follow(fixture.tailer)
        #expect(nextLaunch.skipCount == 0)
    }

    @Test func theIndexerFollowsTheHistoryItIsRegisteredWith() async throws {
        let fixture = try SearchFixture()
        let indexer = fixture.makeIndexer()
        await indexer.follow(fixture.tailer)
        await indexer.start()
        await fixture.tailer.start()
        var operations = fixture.index.operationStream.makeAsyncIterator()
        #expect(await operations.next() == .deleteAll)

        let id = try await fixture.writer.perform(author: .capture) { try $0.record(.text("copied", at: 1)).id }
        #expect(await operations.next() == .index(count: 1, isUpdate: false))
        #expect(await fixture.index.items[id]?.text == "copied")
        await fixture.tailer.stop()
    }

    @Test func aGapInTheHistoryRebuildsTheIndex() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(3)
        let indexer = fixture.makeIndexer()
        await indexer.start()
        await fixture.index.forgetOperations()

        await indexer.rebuild()
        #expect(await fixture.index.operations == [.deleteAll, .index(count: 3, isUpdate: false)])
    }

    // MARK: - Text recognition

    @Test func imagesAreIndexedAgainWithTheirRecognizedWords() async throws {
        let fixture = try SearchFixture()
        let image = try await fixture.recordImage("receipt", at: 1)
        let blank = try await fixture.recordImage("sky", at: 2)
        let unreadable = try await fixture.recordImage("noise", at: 3)
        let indexer = fixture.makeIndexer(recognizer: FakeTextRecognizer(wordsByImage: ["receipt": ["Total", "42"], "sky": []]))
        await indexer.start()
        await indexer.recognitionTask?.value

        #expect(await fixture.index.operations == [
            .deleteAll, .index(count: 3, isUpdate: false), .index(count: 1, isUpdate: true),
        ])
        #expect(await fixture.index.items[image]?.text == "Total 42")
        #expect(await fixture.index.items[image]?.title == "Image")
        #expect(await fixture.index.items[blank]?.text == nil)
        #expect(await fixture.index.items[unreadable]?.text == nil)
        // One rest per image that was read, with or without text; none for the one that failed.
        #expect(fixture.sleeps.durations == [.seconds(2), .seconds(2)])
        #expect(await indexer.recognitionQueue.isEmpty)
    }

    @Test func anImageCopiedWhileRunningIsFoundByItsWordsOnceRead() async throws {
        let fixture = try SearchFixture()
        let indexer = fixture.makeIndexer(recognizer: FakeTextRecognizer(wordsByImage: ["receipt": ["Total", "42"]]))
        await indexer.follow(fixture.tailer)
        await indexer.start()
        await fixture.tailer.start()
        var operations = fixture.index.operationStream.makeAsyncIterator()
        #expect(await operations.next() == .deleteAll)

        let image = try await fixture.recordImage("receipt", at: 1)
        #expect(await operations.next() == .index(count: 1, isUpdate: false))
        #expect(await operations.next() == .index(count: 1, isUpdate: true))
        #expect(await fixture.index.items[image]?.text == "Total 42")
        await fixture.tailer.stop()
    }

    @Test func imagesLeftUnreadAreReadByTheNextLaunch() async throws {
        let fixture = try SearchFixture()
        let image = try await fixture.recordImage("receipt", at: 1)
        // The first launch indexes the image and is over before it reads it.
        let recognizer = FakeTextRecognizer(wordsByImage: ["receipt": ["Total"]])
        await fixture.index.failWrites(after: 2, with: [unavailable, unavailable, unavailable])
        let first = fixture.makeIndexer(recognizer: recognizer)
        await first.start()
        await first.recognitionTask?.value
        await first.stop()
        #expect(await fixture.index.items[image]?.text == nil)

        // The second one finds everything indexed and only probes the index, but reads it.
        let second = fixture.makeIndexer(recognizer: recognizer)
        await second.start()
        await second.recognitionTask?.value
        #expect(await fixture.index.items[image]?.text == "Total")
        #expect(await second.recognitionQueue.isEmpty)

        // And a third has nothing left to read.
        await fixture.index.forgetOperations()
        let third = fixture.makeIndexer(recognizer: recognizer)
        await third.start()
        await third.recognitionTask?.value
        #expect(await fixture.index.operations.isEmpty)
    }

    @Test func changesThatArriveBeforeTheStartAreAppliedByIt() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(1)
        await fixture.makeIndexer().start()
        await fixture.index.forgetOperations()

        // The next launch: the store's history is delivered before the indexer has started.
        let indexer = fixture.makeIndexer()
        let added = try await fixture.writer.perform(author: .capture) { try $0.record(.text("added", at: 10)).id }
        await indexer.storeDidChange([HistoryTransaction(author: .capture, changes: [.init(id: added, kind: .inserted)])])
        #expect(await fixture.index.operations.isEmpty)

        await indexer.start()
        #expect(await fixture.index.operations == [.index(count: 1, isUpdate: false)])
        #expect(await fixture.index.items[added]?.text == "added")
    }

    @Test func recognitionWaitsWhileTheMacIsConstrained() async throws {
        let fixture = try SearchFixture()
        let image = try await fixture.recordImage("receipt", at: 1)
        let conditions = FakeDeviceConditions()
        conditions.setConstrained(true)
        let recognizer = FakeTextRecognizer(wordsByImage: ["receipt": ["Total"]])
        // The Mac stops being constrained after the indexer has waited three times.
        let waits = OSAllocatedUnfairLock(initialState: 0)
        let indexer = SearchIndexer(
            index: fixture.index,
            dataSource: fixture.dataSource,
            recognizer: recognizer,
            config: fixture.config,
            recognitionQueueURL: fixture.recognitionQueueURL,
            conditions: conditions,
            sleep: { duration in
                if duration == SearchIndexer.Metrics.constrainedRecheckInterval,
                   waits.withLock({ $0 += 1; return $0 }) == 3 {
                    conditions.setConstrained(false)
                }
            }
        )
        await indexer.start()
        await indexer.recognitionTask?.value

        #expect(waits.withLock { $0 } == 3)
        #expect(await fixture.index.items[image]?.text == "Total")
        #expect(await indexer.recognitionQueue.isEmpty)
    }

    @Test func aConstrainedMacStillIndexesEverything() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordTexts(3)
        let conditions = FakeDeviceConditions()
        conditions.setConstrained(true)
        await fixture.makeIndexer(conditions: conditions).start()

        #expect(await fixture.index.operations == [.deleteAll, .index(count: 3, isUpdate: false)])
    }

    @Test func theQueueReadSoFarIsSavedWhenTheIndexerStops() async throws {
        let fixture = try SearchFixture()
        _ = try await fixture.recordImage("receipt", at: 1)
        _ = try await fixture.recordImage("sky", at: 2)
        let indexer = fixture.makeIndexer(recognizer: FakeTextRecognizer(wordsByImage: ["receipt": ["Total"], "sky": []]))
        await indexer.start()
        await indexer.recognitionTask?.value
        await indexer.stop()

        // Nothing is left to read, and nothing is saved.
        #expect(RecognitionQueueLog(url: fixture.recognitionQueueURL).restore().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: fixture.recognitionQueueURL.path))
    }

    @Test func aQueueSavedInTheSettingsByAnEarlierVersionMovesToItsFile() async throws {
        let fixture = try SearchFixture()
        let image = try await fixture.recordImage("receipt", at: 1)
        fixture.config.set(JSONConfigValue([image.rawValue]), for: .searchRecognitionQueue)
        // Indexing is done; only the saved queue knows the image is still to be read.
        let indexer = fixture.makeIndexer(recognizer: FakeTextRecognizer(wordsByImage: ["receipt": ["Total"]]))
        await fixture.index.failWrites(after: 2, with: [unavailable, unavailable, unavailable])
        await indexer.start()
        await indexer.recognitionTask?.value

        #expect(fixture.config.value(for: .searchRecognitionQueue).value.isEmpty)
        #expect(RecognitionQueueLog(url: fixture.recognitionQueueURL).restore() == [image])
    }

    @Test func recognitionPausesWhileTheIndexIsUnavailableAndKeepsItsPlace() async throws {
        let fixture = try SearchFixture()
        let image = try await fixture.recordImage("receipt", at: 1)
        let indexer = fixture.makeIndexer(recognizer: FakeTextRecognizer(wordsByImage: ["receipt": ["Total"]]))
        // Emptying and filling the index go through; indexing the recognized words does not.
        await fixture.index.failWrites(after: 2, with: [unavailable, unavailable, unavailable])
        await indexer.start()
        await indexer.recognitionTask?.value
        #expect(await indexer.recognitionQueue.ids == [image])

        // Anything the indexer does next sets the worker going again.
        await indexer.storeDidChange([HistoryTransaction(author: .user, changes: [.init(id: image, kind: .deleted)])])
        #expect(await indexer.recognitionQueue.isEmpty)
    }
}
