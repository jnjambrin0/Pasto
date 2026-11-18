import Foundation
import PastoCore
import PastoFoundation
import PastoUI

/// One measured step of a scenario.
struct StepResult: Codable {
    var name: String
    var wallMs: Double?
    /// CPU the main thread spent during the step.
    var mainCPUms: Double?
    /// Time `SnapshotApplier.apply` took for what the step published.
    var applierMs: Double?
    var residentMB: Double
    var peakMB: Double?
    var count: Int?
    var diskBeforeMB: Double?
    var diskAfterMB: Double?
    var note: String?
}

struct ScenarioResult: Codable {
    var scenario: String
    var steps: [StepResult]
}

private func megabytes(_ bytes: UInt64) -> Double { Double(bytes) / 1_048_576 }
private func megabytes(_ bytes: Int64) -> Double { Double(bytes) / 1_048_576 }

/// The scenarios, each run in a process of its own on a fresh copy of the generated store.
@MainActor
final class Scenarios {
    static let names = ["browse", "capacity", "erase"]
    /// Run first, on the store itself rather than a copy: opening it the first time is what
    /// migrates a store an older version created.
    static let firstOpen = "open"

    private let storeURL: URL
    private let manifest: Manifest
    private var steps: [StepResult] = []

    init(directory: URL, manifest: Manifest) {
        storeURL = directory.appending(path: "Pasto.sqlite")
        self.manifest = manifest
    }

    func run(_ name: String) async throws -> ScenarioResult {
        switch name {
        case Self.firstOpen: _ = try open()
        case "probe": try probe()
        case "browse": try await browse()
        case "capacity": try await massDeletion(name: "capacity-forever-to-month") { try $0.setHistoryCapacity(.month) }
        case "erase": try await massDeletion(name: "erase-history") { try $0.eraseHistory() }
        default: throw UsageError("unknown scenario \(name)")
        }
        return ScenarioResult(scenario: name, steps: steps)
    }

    private func record(_ name: String, wall: Duration? = nil, mainCPU: Duration? = nil, applier: Duration? = nil,
                        peak: UInt64? = nil, count: Int? = nil, diskBefore: Int64? = nil, diskAfter: Int64? = nil, note: String? = nil) {
        steps.append(StepResult(
            name: name,
            wallMs: wall?.milliseconds,
            mainCPUms: mainCPU?.milliseconds,
            applierMs: applier?.milliseconds,
            residentMB: megabytes(Metrics.residentBytes()),
            peakMB: peak.map(megabytes),
            count: count,
            diskBeforeMB: diskBefore.map(megabytes),
            diskAfterMB: diskAfter.map(megabytes),
            note: note
        ))
        let last = steps[steps.count - 1]
        FileHandle.standardError.write(Data("  \(name): \(last.wallMs.map { String(format: "%.2f ms", $0) } ?? "-")\n".utf8))
    }

    private func open() throws -> (PersistentStack, StoreReader, StoreWriter) {
        record("baseline")
        let sampler = PeakMemorySampler()
        sampler.start()
        let (stack, time) = try measure { try PersistentStack(location: .onDisk(storeURL), deviceName: "Stress Mac", appVersion: "stress") }
        record("open-store", wall: time, peak: sampler.stop())
        return (stack, StoreReader(stack: stack), StoreWriter(stack: stack))
    }

    // MARK: - Browsing and everyday writes

    private func browse() async throws {
        let (stack, reader, writer) = try open()

        let sampler = PeakMemorySampler()
        sampler.start()
        let heldBefore = Metrics.mallocInUse()
        let (history, historyTime) = measure { reader.itemCollection(for: .clipboard) }
        let peak = sampler.stop()
        // What the collection keeps once the read is over, its index — built right after, in
        // the background — included.
        try await Task.sleep(for: .milliseconds(500))
        let held = Double(Metrics.mallocInUse() - heldBefore) / 1_048_576
        record("history-collection", wall: historyTime, peak: peak, count: history.snapshot.ids.count,
               note: String(format: "holds %.1f MB", held))

        let pinboard = ListID(rawValue: manifest.pinboardIDs[0])
        let (board, boardTime) = measure { reader.itemCollection(for: pinboard) }
        record("pinboard-collection", wall: boardTime, count: board.snapshot.ids.count)

        var applier = SnapshotApplier<ItemID>()
        let (_, reloadTime) = measure { applier.apply(history.snapshot) }
        record("applier-first-reload", wall: reloadTime)

        let now = Date()
        if let capture = try await publish(history, applier: &applier, {
            _ = try await writer.perform(author: .capture) { try $0.record(Self.text("fresh capture", checksum: "bench-capture", at: now)) }
            return 1
        }) {
            record("publish-capture", wall: capture.wall, mainCPU: capture.mainCPU, applier: capture.applier, count: history.snapshot.ids.count)
        }

        let doomed = history.snapshot.ids[history.snapshot.ids.count / 3]
        if let deletion = try await publish(history, applier: &applier, {
            try await writer.perform(author: .user) { try $0.delete([doomed]) }
            return 1
        }) {
            record("publish-delete", wall: deletion.wall, mainCPU: deletion.mainCPU, applier: deletion.applier, count: history.snapshot.ids.count)
        }

        let middle = manifest.middleItemChecksum
        if let reuse = try await publish(history, applier: &applier, {
            _ = try await writer.perform(author: .capture) { try $0.record(Self.text("copied again", checksum: middle, at: now.addingTimeInterval(1))) }
            return 1
        }) {
            record("publish-reuse-to-front", wall: reuse.wall, mainCPU: reuse.mainCPU, applier: reuse.applier,
                   count: history.snapshot.ids.count, note: "moved from #\(reuse.movedFrom ?? -1)")
        }

        // What a screen of cards reads.
        let screen = Array(history.snapshot.ids.prefix(12))
        var spread: [ItemID] = []
        var random = SplitMix64(seed: 7)
        for _ in 0..<12 { spread.append(history.snapshot.ids[Int(random.next() % UInt64(history.snapshot.ids.count))]) }
        record("items-12-newest-cold", wall: measure { _ = reader.items(screen) }.time)
        record("items-12-newest-warm", wall: median(5) { _ = reader.items(screen) })
        record("items-12-scattered", wall: median(5) { _ = reader.items(spread) })
        let image = ItemID(rawValue: manifest.imageItemID)
        let longText = ItemID(rawValue: manifest.longTextItemID)
        let imageBytes = reader.pasteboardItems(for: image)?.reduce(0) { $0 + $1.dataByType.values.reduce(0) { $0 + $1.count } } ?? 0
        record("pasteboardItems-image", wall: median(3) { _ = reader.pasteboardItems(for: image) }, note: "\(imageBytes / 1024) KB")
        record("pasteboardItems-long-text", wall: median(3) { _ = reader.pasteboardItems(for: longText) })

        // A capture as `HistoryManager` writes it: the item, then retention with a year's capacity.
        // Every snapshot goes through the applier as it arrives, as the panel takes them.
        let yearCutoff: @Sendable (Date) -> Date = { $0.addingTimeInterval(-365 * 24 * 3600) }
        _ = try await publish(history, applier: &applier) {
            try await writer.perform(author: .maintenance) { try $0.deleteHistory(olderThan: yearCutoff(now)) }
        }
        var captureTimes: [Duration] = []
        for index in 0..<5 {
            let timestamp = now.addingTimeInterval(10 + Double(index))
            let item = Self.text("capture \(index)", checksum: "bench-capture-\(index)", at: timestamp)
            _ = try await publish(history, applier: &applier) {
                let (_, time) = try await measure {
                    try await writer.perform(author: .capture) { context in
                        _ = try context.record(item)
                        return try context.deleteHistory(olderThan: yearCutoff(timestamp))
                    }
                }
                captureTimes.append(time)
                return 1
            }
        }
        record("capture-write+trim", wall: captureTimes.sorted()[2], note: "median of 5, the write alone")

        // Retention after a capture that lets a handful of old items expire: the cutoff moves
        // past the next six items of a year spread evenly over the store.
        let cutoff = yearCutoff(now).addingTimeInterval(6 * 365 * 24 * 3600 / Double(manifest.count))
        if let trim = try await publish(history, applier: &applier, {
            try await writer.perform(author: .maintenance) { try $0.deleteHistory(olderThan: cutoff) }
        }) {
            record("trim-few-expired", wall: trim.wall, mainCPU: trim.mainCPU, applier: trim.applier, count: history.snapshot.ids.count)
        }

        // Two snapshots several writes apart — a change too big for the shortcuts — go through
        // the general algorithm: what the applier costs when a publication carries many edits.
        let far = CollectionSnapshot(ids: Array(history.snapshot.ids.dropFirst(5).dropLast(20)) + [ItemID(rawValue: "far")])
        var cold = SnapshotApplier<ItemID>()
        _ = cold.apply(history.snapshot)
        let (_, farTime) = measure { _ = cold.apply(far) }
        record("applier-general-fallback", wall: farTime, note: "5 removed at the front, 20 at the back, 1 added")
        withExtendedLifetime(board) {}

        try await purgeHistory(stack: stack, writer: writer)
    }

    // MARK: - Probe

    /// Not part of `measure`: what the parts of publishing a change cost on the identifiers the
    /// history collection holds, as they come from the store and as native strings.
    private func probe() throws {
        let (_, reader, _) = try open()
        // The names search suggests at every keystroke: the first time, from a file the system
        // has not cached, and then.
        let (names, namesTime) = measure { reader.sourceApplicationNames() + reader.deviceNames() }
        record("probe-names-first", wall: namesTime, count: names.count)
        record("probe-names", wall: median(5) { _ = reader.sourceApplicationNames() + reader.deviceNames() })

        let bridged = reader.itemCollection(for: .clipboard).snapshot.ids
        let (native, nativeTime) = measure {
            bridged.map { id -> ItemID in
                var raw = id.rawValue
                raw.makeContiguousUTF8()
                return ItemID(rawValue: raw)
            }
        }
        record("probe-make-native", wall: nativeTime, count: native.count)
        for (label, ids) in [("bridged", bridged), ("native", native)] {
            let old = CollectionSnapshot(ids: ids)
            let inserted = CollectionSnapshot(ids: [ItemID(rawValue: "NEW")] + ids)
            record("probe-\(label)-diff-insert-front", wall: median(3) { _ = CollectionChanges.between(old, inserted) })
            var shuffled = ids
            shuffled.swapAt(10, ids.count - 10)
            shuffled.swapAt(20, ids.count - 20)
            shuffled.swapAt(30, ids.count - 30)
            shuffled.swapAt(40, ids.count - 40)
            shuffled.swapAt(50, ids.count - 50)
            record("probe-\(label)-diff-five-swaps", wall: median(3) { _ = CollectionChanges.between(old, CollectionSnapshot(ids: shuffled)) })
            var scrambled = ids
            var random = SplitMix64(seed: 3)
            for _ in 0..<50 {
                scrambled.swapAt(Int(random.next() % UInt64(ids.count)), Int(random.next() % UInt64(ids.count)))
            }
            record("probe-\(label)-diff-fifty-swaps", wall: median(3) { _ = CollectionChanges.between(old, CollectionSnapshot(ids: scrambled)) })
            // As the applier asks: with its limit of 300 changes.
            let limit = SnapshotApplier<ItemID>.batchUpdateLimit
            record("probe-\(label)-diff-fifty-swaps-limited", wall: median(3) {
                _ = CollectionChanges.between(old, CollectionSnapshot(ids: scrambled), changeLimit: limit)
            })
            let pasted = Set(stride(from: 40, to: ids.count, by: ids.count / 100).prefix(100).map { ids[$0] })
            let toFront = CollectionSnapshot(ids: ids.filter(pasted.contains) + ids.filter { !pasted.contains($0) })
            record("probe-\(label)-diff-hundred-to-front-limited", wall: median(3) {
                _ = CollectionChanges.between(old, toFront, changeLimit: limit)
            })
            var overLimit = ids
            for _ in 0..<400 {
                overLimit.swapAt(Int(random.next() % UInt64(ids.count)), Int(random.next() % UInt64(ids.count)))
            }
            record("probe-\(label)-diff-over-limit-limited", wall: median(3) {
                _ = CollectionChanges.between(old, CollectionSnapshot(ids: overLimit), changeLimit: limit)
            })
            record("probe-\(label)-set", wall: median(3) { _ = Set(ids) })
            record("probe-\(label)-copy-insert", wall: median(3) {
                var copy = ids
                copy.insert(ItemID(rawValue: "NEW"), at: 0)
                withExtendedLifetime(copy) {}
            })
            record("probe-\(label)-equal-scan", wall: median(3) {
                var equal = 0
                for index in ids.indices where ids[index] == old.ids[index] { equal += 1 }
                precondition(equal == ids.count)
            })
        }
    }

    // MARK: - Mass deletions

    private func massDeletion(name: String, _ work: @escaping @Sendable (WritingContext) throws -> Int) async throws {
        let (_, reader, writer) = try open()
        let history = reader.itemCollection(for: .clipboard)
        var applier = SnapshotApplier<ItemID>()
        _ = applier.apply(history.snapshot)
        var applierTime = Duration.zero
        var publishes = 0
        history.onChange = { snapshot in
            applierTime += measure { _ = applier.apply(snapshot) }.time
            publishes += 1
        }
        record("history-collection", count: history.snapshot.ids.count)

        let disk = Metrics.storeBytes(at: storeURL)
        let sampler = PeakMemorySampler()
        sampler.start()
        let watchdog = MainThreadWatchdog()
        watchdog.start()
        let cpu = Metrics.mainThreadCPU()
        let clock = ContinuousClock()
        let start = clock.now
        let affected = try await writer.perform(author: .user, work)
        let written = clock.now - start
        let expected = reader.itemCount(in: .clipboard)
        while history.snapshot.ids.count != expected, clock.now - start < .seconds(600) {
            try await Task.sleep(for: .milliseconds(5))
        }
        let visible = clock.now - start
        let mainCPU = Metrics.mainThreadCPU() - cpu
        let stall = watchdog.stop()
        let peak = sampler.stop()
        let after = Metrics.storeBytes(at: storeURL)
        let pages = Metrics.pages(of: storeURL)
        record(name, wall: written, mainCPU: mainCPU, applier: applierTime, peak: peak, count: affected,
               diskBefore: disk.database + disk.external, diskAfter: after.database + after.external,
               note: String(format: "visible after %.0f ms, %d publishes, longest main-thread stall %.0f ms; db %.0f→%.0f MB (%d of %d pages free), external %.0f→%.0f MB",
                             visible.milliseconds, publishes, stall.milliseconds, megabytes(disk.database), megabytes(after.database),
                             pages.free, pages.total, megabytes(disk.external), megabytes(after.external)))

        // The daily round of maintenance, right away: what is left to give back.
        let (report, maintenanceTime) = try await measure { try await writer.performMaintenance() }
        let maintained = Metrics.storeBytes(at: storeURL)
        let pagesAfter = Metrics.pages(of: storeURL)
        record("maintenance-after", wall: maintenanceTime,
               diskBefore: after.database + after.external, diskAfter: maintained.database + maintained.external,
               note: String(format: "reclaimed %.0f MB%@; db %.0f MB (%d of %d pages free)",
                             Double(report?.bytesReclaimed ?? 0) / 1_048_576, report?.vacuumed == true ? " (rebuilt)" : "",
                             megabytes(maintained.database), pagesAfter.free, pagesAfter.total))
    }

    // MARK: - Persistent history

    /// Purging the persistent history, as maintenance does once a day, but all of it: the
    /// generated history is a few hours old, and this measures what a year's worth costs.
    private func purgeHistory(stack: PersistentStack, writer: StoreWriter) async throws {
        let suite = "pastostress-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let tailer = HistoryTailer(stack: stack, config: ConfigStore(defaults: defaults))
        let before = Metrics.storeBytes(at: storeURL)
        let (_, purgeTime) = try await measure { try await tailer.purge(before: Date()) }
        let (report, maintenanceTime) = try await measure { try await writer.performMaintenance() }
        let after = Metrics.storeBytes(at: storeURL)
        record("purge-history", wall: purgeTime, diskBefore: before.database, diskAfter: after.database,
               note: String(format: "then maintenance %.0f ms reclaiming %.0f MB (database only)",
                             maintenanceTime.milliseconds, Double(report?.bytesReclaimed ?? 0) / 1_048_576))
    }

    // MARK: - Helpers

    private struct Publication {
        var wall: Duration
        var mainCPU: Duration
        var applier: Duration
        var movedFrom: Int?
    }

    /// Runs `write` and measures what publishing its result costs the main thread, up to the
    /// collection's new snapshot having gone through the applier as the panel would apply it.
    /// `write` returns how many items it changed; with none, nothing is published and `nil` is
    /// returned.
    private func publish(
        _ collection: ItemCollection,
        applier: inout SnapshotApplier<ItemID>,
        _ write: () async throws -> Int
    ) async throws -> Publication? {
        let (snapshots, continuation) = AsyncStream.makeStream(of: CollectionSnapshot<ItemID>.self)
        collection.onChange = { continuation.yield($0) }
        defer { collection.onChange = nil }

        let clock = ContinuousClock()
        let cpu = Metrics.mainThreadCPU()
        let start = clock.now
        guard try await write() > 0 else { return nil }
        var iterator = snapshots.makeAsyncIterator()
        guard let snapshot = await iterator.next() else { throw CancellationError() }
        let (application, applierTime) = measure { applier.apply(snapshot) }
        let wall = clock.now - start
        let mainCPU = Metrics.mainThreadCPU() - cpu
        var movedFrom: Int?
        if case .changes(let changeset) = application { movedFrom = changeset.moves.first?.from }
        return Publication(wall: wall, mainCPU: mainCPU, applier: applierTime, movedFrom: movedFrom)
    }

    private func median(_ runs: Int, _ body: () -> Void) -> Duration {
        (0..<runs).map { _ in measure(body).time }.sorted()[runs / 2]
    }

    nonisolated static func text(_ text: String, checksum: String, at date: Date) -> NewItem {
        NewItem(
            type: .text,
            checksum: checksum,
            preview: .text(TextPreview(text: text, characterCount: text.count)),
            pasteboardItems: [PasteboardItemSnapshot(types: ["public.utf8-plain-text"], dataByType: ["public.utf8-plain-text": Data(text.utf8)])],
            timestamp: date
        )
    }
}

struct UsageError: Error, CustomStringConvertible {
    var description: String
    init(_ description: String) { self.description = description }
}
