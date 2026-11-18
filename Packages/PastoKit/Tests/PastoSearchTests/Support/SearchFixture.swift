import Foundation
import os
import PastoCore
import PastoFoundation
import PastoRecognition
@testable import PastoSearch

/// An in-memory store, a fake index and settings of their own, and indexers built on them.
struct SearchFixture {
    let stack: PersistentStack
    let writer: StoreWriter
    let tailer: HistoryTailer
    let config: ConfigStore
    let index: FakeSearchIndex
    let sleeps = SleepRecorder()
    private let ephemeral = EphemeralDefaults()

    init(index: FakeSearchIndex = FakeSearchIndex()) throws {
        stack = try PersistentStack(location: .inMemory, deviceName: "Test Mac", appVersion: "1.0")
        writer = StoreWriter(stack: stack)
        config = ConfigStore(defaults: ephemeral.defaults)
        tailer = HistoryTailer(stack: stack, config: config)
        self.index = index
    }

    /// Where the indexers of this fixture keep their queue of images to read.
    var recognitionQueueURL: URL {
        ephemeral.directory.appending(path: "SearchRecognitionQueue.txt")
    }

    /// The store, as the indexer reads it.
    var dataSource: StoreIndexerDataSource {
        StoreIndexerDataSource(reader: IndexableItemReader(stack: stack), tailer: tailer)
    }

    /// A new indexer on the same store, index and settings: what the next launch would create.
    func makeIndexer(
        recognizer: FakeTextRecognizer = FakeTextRecognizer(),
        dataSource: (any SearchIndexerDataSource)? = nil,
        conditions: FakeDeviceConditions = FakeDeviceConditions()
    ) -> SearchIndexer {
        SearchIndexer(
            index: index,
            dataSource: dataSource ?? self.dataSource,
            recognizer: recognizer,
            config: config,
            recognitionQueueURL: recognitionQueueURL,
            conditions: conditions,
            sleep: sleeps.sleep
        )
    }

    /// Records `count` text items, the first one the oldest, and returns their identifiers.
    func recordTexts(_ count: Int) async throws -> [ItemID] {
        try await writer.perform(author: .capture) { context in
            try (1...count).map { try context.record(.text("text \($0)", at: TimeInterval($0))).id }
        }
    }

    func recordImage(_ bytes: String, at second: TimeInterval) async throws -> ItemID {
        try await writer.perform(author: .capture) { context in
            try context.record(NewItem(
                type: .image,
                checksum: bytes,
                preview: .unknown,
                pasteboardItems: [PasteboardItemSnapshot(types: ["public.png"], dataByType: ["public.png": Data(bytes.utf8)])],
                timestamp: Date(timeIntervalSinceReferenceDate: second)
            )).id
        }
    }

    var savedState: IndexingState? {
        config.value(for: .searchIndexingState).value
    }
}

extension NewItem {
    /// A text item whose checksum is its text.
    static func text(_ text: String, at second: TimeInterval) -> NewItem {
        NewItem(
            type: .text,
            checksum: text,
            preview: .text(TextPreview(text: text, characterCount: text.count)),
            pasteboardItems: [
                PasteboardItemSnapshot(types: ["public.utf8-plain-text"], dataByType: ["public.utf8-plain-text": Data(text.utf8)]),
            ],
            timestamp: Date(timeIntervalSinceReferenceDate: second)
        )
    }
}

/// A Mac that is constrained when the test says so, never otherwise: the tests must not depend on
/// the Mac they run on.
final class FakeDeviceConditions: DeviceConditions {
    private let constrained = OSAllocatedUnfairLock(initialState: false)

    var isConstrained: Bool {
        constrained.withLock { $0 }
    }

    func setConstrained(_ value: Bool) {
        constrained.withLock { $0 = value }
    }
}

/// Stands in for the clock: remembers every wait and returns at once.
final class SleepRecorder: Sendable {
    private let recorded = OSAllocatedUnfairLock(initialState: [Duration]())

    var durations: [Duration] {
        recorded.withLock { $0 }
    }

    var sleep: @Sendable (Duration) async throws -> Void {
        { [recorded] duration in
            try Task.checkCancellation()
            // The probe's timeout must lose to the probe, as it does in real time.
            if duration == SearchIndexer.Metrics.probeTimeout {
                try await Task.sleep(for: .seconds(3600))
            }
            recorded.withLock { $0.append(duration) }
        }
    }
}

/// Reads the store like the real data source, counting how often the indexer skips the history.
struct CountingDataSource: SearchIndexerDataSource {
    private let base: any SearchIndexerDataSource
    private let skips = OSAllocatedUnfairLock(initialState: 0)

    init(_ base: any SearchIndexerDataSource) {
        self.base = base
    }

    var skipCount: Int {
        skips.withLock { $0 }
    }

    func storeIdentifier() async -> String? {
        await base.storeIdentifier()
    }

    func itemIDs(before date: Date?) async throws -> [ItemID] {
        try await base.itemIDs(before: date)
    }

    func items(_ ids: [ItemID]) async throws -> [IndexableItem] {
        try await base.items(ids)
    }

    func imageData(for id: ItemID) async throws -> Data? {
        try await base.imageData(for: id)
    }

    func skipHistoryToPresent() async {
        skips.withLock { $0 += 1 }
        await base.skipHistoryToPresent()
    }
}

/// Recognizes what the tests say is in each image.
struct FakeTextRecognizer: TextRecognizer {
    /// Words by the image's bytes read as UTF-8; an image that is not listed fails to be read.
    var wordsByImage: [String: [String]] = [:]

    func recognizeWords(in imageData: Data) async throws -> [String] {
        guard let words = wordsByImage[String(decoding: imageData, as: UTF8.self)] else {
            throw TextRecognitionError.imageDecodeFailed
        }
        return words
    }
}
