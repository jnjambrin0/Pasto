import AppKit
import Foundation
@_spi(Benchmarks) import PastoCore
import PastoFoundation

// The restore writes on a named pasteboard of the benchmark's own, exactly as the app writes the
// general one (`NamedPasteboardWriter`), so the transfer to the pasteboard server is measured
// without touching the user's clipboard.

enum RestoreScenario {
    /// Opens a store a capture run left behind and restores its item, as pasting it does.
    @MainActor
    static func run(storeDirectory: URL, item: String) async throws {
        let stack = try PersistentStack(location: .onDisk(storeDirectory.appending(path: "Pasto.sqlite")), deviceName: "Bench", appVersion: "bench")
        let reader = StoreReader(stack: stack)
        let writer = StoreWriter(stack: stack)
        let suiteName = "jnjambrino.Pasto.CaptureBench.\(UUID().uuidString)"
        defer { UserDefaults.standard.removePersistentDomain(forName: suiteName) }
        let config = ConfigStore(defaults: UserDefaults(suiteName: suiteName)!)
        let pasteboard = NamedPasteboardWriter(name: "jnjambrino.Pasto.CaptureBench.\(UUID().uuidString)")
        defer { pasteboard.release() }
        let temporary = storeDirectory.appending(path: "tmp", directoryHint: .isDirectory)
        let restorer = ItemRestorer(reader: reader, writer: writer, pasteboard: pasteboard, config: config, temporaryDirectory: temporary)
        let id = ItemID(rawValue: item)
        guard let stored = reader.item(id) else { throw BenchError("no item \(item) in \(storeDirectory.path)") }

        let baseline = ProcessMetrics.resident().current
        let baselineFootprint = ProcessMetrics.footprint().current
        let baselineHeap = ProcessMetrics.heapInUse()
        let sampler = PeakSampler()
        sampler.start()
        let start = ContinuousClock.now
        let restored = restorer.restore([id], options: [])
        let elapsed = ContinuousClock.now - start
        // What the application the ⌘V lands in reads last: the file URL of the image copy, which
        // may be a promise kept once the copy is written.
        let fileURL = pasteboard.pasteboard.data(forType: NSPasteboard.PasteboardType("public.file-url"))
        let fileURLElapsed = ContinuousClock.now - start
        let peaks = sampler.stop()
        guard restored else { throw BenchError("nothing restored") }

        try await Task.sleep(for: .seconds(2))
        let retained = ProcessMetrics.resident().current
        let imagesFolder = temporary.appending(path: "images")
        let imageFiles = (try? FileManager.default.contentsOfDirectory(atPath: imagesFolder.path)) ?? []
        let permissions = (try? FileManager.default.attributesOfItem(atPath: imagesFolder.path)[.posixPermissions] as? Int)
            .map { String($0, radix: 8) } ?? "-"

        ResultLine(scenario: "restore", values: [
            "main_thread_ms": elapsed.milliseconds,
            "file_url_ms": fileURL == nil ? -1 : fileURLElapsed.milliseconds,
            "baseline_mb": baseline.megabytes,
            "peak_delta_mb": (peaks.resident - min(peaks.resident, baseline)).megabytes,
            "footprint_peak_delta_mb": (peaks.footprint - min(peaks.footprint, baselineFootprint)).megabytes,
            "retained_mb": (retained - min(retained, baseline)).megabytes,
            "heap_peak_delta_mb": (peaks.heap - min(peaks.heap, baselineHeap)).megabytes,
            "retained_heap_mb": (ProcessMetrics.heapInUse() - min(ProcessMetrics.heapInUse(), baselineHeap)).megabytes,
            "temporary_files": Double(imageFiles.count),
        ], notes: ["type": "\(stored.type)", "images_folder_mode": permissions]).print()
    }

    /// Reads the item of a store a capture run left behind as the search indexer does, to index
    /// its text.
    static func indexRead(storeDirectory: URL, item: String) async throws {
        let stack = try PersistentStack(location: .onDisk(storeDirectory.appending(path: "Pasto.sqlite")), deviceName: "Bench", appVersion: "bench")
        let reader = IndexableItemReader(stack: stack)
        let id = ItemID(rawValue: item)

        let baselineHeap = ProcessMetrics.heapInUse()
        let baselineFootprint = ProcessMetrics.footprint().current
        let sampler = PeakSampler()
        sampler.start()
        let start = ContinuousClock.now
        let items = try await reader.items([id])
        let elapsed = ContinuousClock.now - start
        let peaks = sampler.stop()
        guard let read = items.first else { throw BenchError("no item \(item) in \(storeDirectory.path)") }

        ResultLine(scenario: "index-read", values: [
            "read_ms": elapsed.milliseconds,
            "heap_peak_delta_mb": (peaks.heap - min(peaks.heap, baselineHeap)).megabytes,
            "footprint_peak_delta_mb": (peaks.footprint - min(peaks.footprint, baselineFootprint)).megabytes,
            "retained_heap_mb": (ProcessMetrics.heapInUse() - min(ProcessMetrics.heapInUse(), baselineHeap)).megabytes,
            "text_characters": Double(read.text?.count ?? 0),
        ], notes: ["type": "\(read.type)"]).print()
    }
}
