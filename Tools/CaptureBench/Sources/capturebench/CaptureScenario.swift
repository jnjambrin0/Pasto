import Foundation
import os
@_spi(Benchmarks) import PastoCore
import PastoFoundation

/// The application capture believes the copy came from.
struct BenchApplication: FrontmostApplicationProviding {
    func frontmostApplication() -> FrontmostApplication? {
        FrontmostApplication(bundleIdentifier: "com.apple.TextEdit", name: "TextEdit", icon: nil)
    }
}

/// The whole capture pipeline as the app runs it — `SystemPasteboard` polling and settling with
/// the app's timings, `HistoryManager`, the store on disk — over the benchmark's pasteboard.
@MainActor
final class CaptureRig {
    let directory: URL
    let stack: PersistentStack
    let writer: StoreWriter
    let config: ConfigStore
    let source = FilePasteboardSource()
    let pasteboard: SystemPasteboard
    let manager: HistoryManager
    private let suiteName = "jnjambrino.Pasto.CaptureBench.\(UUID().uuidString)"
    private let events: AsyncStream<CaptureEvent>

    init(directory: URL) async throws {
        self.directory = directory
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        stack = try PersistentStack(location: .onDisk(directory.appending(path: "Pasto.sqlite")), deviceName: "Bench", appVersion: "bench")
        writer = StoreWriter(stack: stack)
        config = ConfigStore(defaults: UserDefaults(suiteName: suiteName)!)
        config.set(false, for: .isLinkPreviewsEnabled)
        pasteboard = SystemPasteboard(source: source, configuration: .standard, config: config, applications: BenchApplication())
        manager = HistoryManager(pasteboard: pasteboard, writer: writer, config: config)
        events = await manager.events()
        await manager.start()
        // The baseline is taken one poll after starting.
        try await Task.sleep(for: .milliseconds(400))
    }

    func tearDown() {
        UserDefaults.standard.removePersistentDomain(forName: suiteName)
    }

    /// Waits for the next capture.
    func nextCapture() async -> PasteboardCapture? {
        for await event in events {
            if case .captured(let capture) = event { return capture }
        }
        return nil
    }
}

enum CaptureScenario {
    /// Copies the payload once and reports how long it took to reach the history and how much
    /// memory it needed on top of what the process held before.
    @MainActor
    static func run(kind: PayloadKind, megabytes: Int, payloads: URL, storeDirectory: URL, followedBySmallCopy: Bool) async throws {
        let payload = try Payload.prepared(kind, megabytes: megabytes, in: payloads)
        let rig = try await CaptureRig(directory: storeDirectory)
        defer { rig.tearDown() }

        let baseline = ProcessMetrics.resident().current
        let baselineFootprint = ProcessMetrics.footprint().current
        let baselineHeap = ProcessMetrics.heapInUse()
        let sampler = PeakSampler()
        sampler.start()

        let smallCopy = OSAllocatedUnfairLockBox<ContinuousClock.Instant?>(nil)
        let copiedAt = ContinuousClock.now
        rig.source.copy([payload.pasteboardItem]) { [source = rig.source] in
            guard followedBySmallCopy else { return }
            // Copied the moment the large read is over: it waits behind the large capture.
            smallCopy.set(.now)
            source.copy([[.init(type: "public.utf8-plain-text", content: .bytes(Data("small \(UUID())".utf8)))]])
        }
        guard let capture = await rig.nextCapture() else { throw BenchError("no capture") }
        let capturedAt = ContinuousClock.now
        let peaks = sampler.stop()

        var values: [String: Double] = [
            "payload_mb": payload.byteCount.megabytes,
            "latency_ms": (capturedAt - copiedAt).milliseconds,
            "baseline_mb": baseline.megabytes,
            "peak_delta_mb": (peaks.resident - min(peaks.resident, baseline)).megabytes,
            "footprint_peak_delta_mb": (peaks.footprint - min(peaks.footprint, baselineFootprint)).megabytes,
            "heap_peak_delta_mb": (peaks.heap - min(peaks.heap, baselineHeap)).megabytes,
            "lifetime_peak_mb": ProcessMetrics.resident().peak.megabytes,
            "ru_maxrss_mb": ProcessMetrics.maxRSS().megabytes,
        ]
        values["peak_ratio"] = values["peak_delta_mb"]! / max(values["payload_mb"]!, 0.001)
        values["heap_peak_ratio"] = values["heap_peak_delta_mb"]! / max(values["payload_mb"]!, 0.001)
        if let fetch = rig.source.fetchInterval {
            values["read_ms"] = (fetch.last - fetch.first).milliseconds
            values["after_read_ms"] = (capturedAt - fetch.last).milliseconds
        }

        if followedBySmallCopy {
            guard await rig.nextCapture() != nil, let copied = smallCopy.value else { throw BenchError("no small capture") }
            values["small_latency_ms"] = (ContinuousClock.now - copied).milliseconds
        }

        // What stays once capture is over.
        try await Task.sleep(for: .seconds(2))
        values["retained_mb"] = (ProcessMetrics.resident().current - min(ProcessMetrics.resident().current, baseline)).megabytes
        values["retained_footprint_mb"] = (ProcessMetrics.footprint().current - min(ProcessMetrics.footprint().current, baselineFootprint)).megabytes
        values["retained_heap_mb"] = (ProcessMetrics.heapInUse() - min(ProcessMetrics.heapInUse(), baselineHeap)).megabytes

        ResultLine(
            scenario: "capture",
            values: values,
            notes: ["kind": kind.rawValue, "item": capture.itemID.rawValue, "type": "\(capture.itemType)", "store": storeDirectory.path]
        ).print()
    }
}

extension CaptureScenario {
    /// The two halves of a capture after the read, timed apart: turning the snapshot into an
    /// item (type, checksum, preview) and storing it.
    @MainActor
    static func phases(kind: PayloadKind, megabytes: Int, payloads: URL, storeDirectory: URL) async throws {
        let payload = try Payload.prepared(kind, megabytes: megabytes, in: payloads)
        let rig = try await CaptureRig(directory: storeDirectory)
        defer { rig.tearDown() }
        var dataByType: [String: Data] = [:]
        for representation in payload.representations {
            dataByType[representation.type] = try FileHandle(forReadingFrom: representation.file).readToEnd()
        }
        let snapshot = PasteboardItemSnapshot(types: payload.representations.map(\.type), dataByType: dataByType)

        let baseline = ProcessMetrics.footprint().current
        let baselineHeap = ProcessMetrics.heapInUse()
        let sampler = PeakSampler()
        sampler.start()
        let start = ContinuousClock.now
        guard let item = await NewItem.captured(from: [snapshot], at: Date()) else { throw BenchError("no item") }
        let built = ContinuousClock.now
        let builtPeak = sampler.stop()
        let builtHeap = ProcessMetrics.heapInUse()
        sampler.start()
        _ = try await rig.writer.perform(author: .capture) { [item] context in try context.record(item) }
        let stored = ContinuousClock.now
        let storedPeak = sampler.stop()
        ResultLine(scenario: "phases", values: [
            "payload_mb": payload.byteCount.megabytes,
            "build_ms": (built - start).milliseconds,
            "store_ms": (stored - built).milliseconds,
            "build_peak_delta_mb": (builtPeak.footprint - min(builtPeak.footprint, baseline)).megabytes,
            "store_peak_delta_mb": (storedPeak.footprint - min(storedPeak.footprint, baseline)).megabytes,
            "build_heap_peak_delta_mb": (builtPeak.heap - min(builtPeak.heap, baselineHeap)).megabytes,
            "build_heap_left_mb": (builtHeap - min(builtHeap, baselineHeap)).megabytes,
            "store_heap_peak_delta_mb": (storedPeak.heap - min(storedPeak.heap, baselineHeap)).megabytes,
        ], notes: ["kind": kind.rawValue, "type": "\(item.type)"]).print()
    }
}

/// A value shared with a closure that runs on another thread.
final class OSAllocatedUnfairLockBox<Value: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        lock = OSAllocatedUnfairLock(initialState: value)
    }

    var value: Value { lock.withLock { $0 } }

    func set(_ value: Value) {
        lock.withLock { $0 = value }
    }
}
