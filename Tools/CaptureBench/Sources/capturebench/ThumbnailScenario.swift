import CoreGraphics
import Foundation
import ImageIO
import PastoCoreUI
import UniformTypeIdentifiers

/// Scrolling a strip of image cards: cells come into view, ask the shared decoder for their
/// thumbnail and cancel the request when they leave, as `ImageRequest` does.
enum ThumbnailScenario {
    /// Cards on screen at once (a 1728-point screen holds about eight 220-point cards).
    static let visibleCells = 9

    @MainActor
    static func run(count: Int, cardsPerSecond: Double, byteLimit: Int?) async throws {
        let thumbnails = try makeThumbnails(count: count)
        let decoder = byteLimit.map { ImageDecoder(byteLimit: $0) } ?? ImageDecoder()

        final class Cell {
            var task: Task<Void, Never>?
            var image: CGImage?
        }
        var cells: [Int: Cell] = [:]
        var decoded = 0
        var shownWithoutWaiting = 0
        var leftWithoutImage = 0

        let baseline = ProcessMetrics.resident().current
        let sampler = PeakSampler()
        sampler.start()
        let interval = Duration.seconds(1 / cardsPerSecond)
        let start = ContinuousClock.now

        for first in 0..<(count + visibleCells) {
            // The card leaving on the left lets go of its request and its image.
            if let leaving = cells.removeValue(forKey: first - 1) {
                leaving.task?.cancel()
                if leaving.image == nil { leftWithoutImage += 1 }
            }
            // The card entering on the right asks for its thumbnail.
            let entering = first + visibleCells - 1
            if entering < count {
                let cell = Cell()
                cells[entering] = cell
                let data = thumbnails[entering]
                if let image = decoder.cachedImage(for: data) {
                    cell.image = image
                    shownWithoutWaiting += 1
                } else {
                    cell.task = Task {
                        let image = await decoder.image(for: data)
                        guard !Task.isCancelled else { return }
                        cell.image = image
                        decoded += 1
                    }
                }
            }
            try await Task.sleep(until: start + interval * Double(first + 1), clock: .continuous)
        }
        let elapsed = ContinuousClock.now - start
        let peaks = sampler.stop()
        let afterScroll = ProcessMetrics.resident().current

        // Going back over the last screenful finds it in memory.
        var hitsBack = 0
        for index in max(0, count - visibleCells)..<count where decoder.cachedImage(for: thumbnails[index]) != nil {
            hitsBack += 1
        }

        ResultLine(scenario: "thumbnails", values: [
            "cards": Double(count),
            "byte_limit_mb": Double(byteLimit ?? -1) / 1_048_576,
            "scroll_s": elapsed.milliseconds / 1000,
            "baseline_mb": baseline.megabytes,
            "peak_delta_mb": (peaks.resident - min(peaks.resident, baseline)).megabytes,
            "after_scroll_delta_mb": (afterScroll - min(afterScroll, baseline)).megabytes,
            "decoded": Double(decoded),
            "left_without_image": Double(leftWithoutImage),
            "last_screen_cached": Double(hitsBack),
        ]).print()
    }

    /// `count` distinct thumbnails the size capture stores (560 × 460 px, JPEG at 0.6): one image
    /// with a different tail on each, which decoders ignore and the cache does not.
    private static func makeThumbnails(count: Int) throws -> [Data] {
        let width = 560, height = 460
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw BenchError("no context") }
        for row in 0..<46 {
            for column in 0..<56 {
                context.setFillColor(CGColor(red: Double(row) / 46, green: Double(column) / 56, blue: 0.5, alpha: 1))
                context.fill(CGRect(x: column * 10, y: row * 10, width: 10, height: 10))
            }
        }
        guard let image = context.makeImage() else { throw BenchError("no image") }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw BenchError("no destination")
        }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.6] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BenchError("no JPEG") }
        let base = output as Data
        return (0..<count).map { index in
            var data = base
            withUnsafeBytes(of: UInt64(index)) { data.append(contentsOf: $0) }
            return data
        }
    }
}
