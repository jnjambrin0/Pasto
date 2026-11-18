import CoreGraphics
import Foundation
import ImageIO
import os
import PastoCore
import UniformTypeIdentifiers

/// What a generated store holds, saved next to it so that measurements know where to look.
struct Manifest: Codable {
    var count: Int
    var seed: UInt64
    var pinboardIDs: [String]
    /// Items of each kind, by chronological position.
    var middleItemChecksum: String
    var imageItemID: String
    var longTextItemID: String
    var generationSeconds: Double
    var generatedAt: Date
}

/// The mix of a year of heavy use.
struct GeneratorOptions {
    var count = 300_000
    var seed: UInt64 = 2026
    /// Multiplies the size of every image; 1 gives 0.2–5 MB.
    var imageScale = 1.0
    var pinboardCount = 10
    var pinnedFromHistory = 1_800
    var pinboardOnly = 200
    var batchSize = 250
}

/// Fills a store on disk through the app's own writer, as a year of captures would.
///
/// Items enter through `create(_:in:)` on a scratch pinboard and `touch(_:at:)`, which only use
/// indexed lookups, instead of `record(_:)`, whose newest-item fetch scans the whole table on a
/// store without a `timestamp` index and would make generating quadratic. The result is the same
/// rows `record(_:)` leaves (plus an `updatedAt`).
@MainActor
final class Generator {
    private let options: GeneratorOptions
    private var random: SplitMix64
    private let clock = OSAllocatedUnfairLock(initialState: Date())
    private let images: [ImageSample]
    private let corpus: String
    private let applications: [SourceApplication]

    init(options: GeneratorOptions) {
        self.options = options
        random = SplitMix64(seed: options.seed)
        images = ImageSample.pool(count: 40, scale: options.imageScale, random: &random)
        corpus = Self.corpus(byteCount: 600_000, random: &random)
        let icon = ImageSample.png(width: 32, height: 32, noise: false, random: &random)
        applications = (1...24).map { index in
            SourceApplication(
                bundleIdentifier: String(format: "com.example.stress.app%02d", index),
                name: String(format: "App %02d", index),
                colorCode: Int64(0x10_00_00 + index * 0x05_03_07),
                iconData: icon
            )
        }
    }

    func generate(into directory: URL) async throws -> Manifest {
        let started = ContinuousClock.now
        try? FileManager.default.removeItem(at: directory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let storeURL = directory.appending(path: "Pasto.sqlite")

        let stack = try PersistentStack(location: .onDisk(storeURL), deviceName: "Stress Mac", appVersion: "stress")
        let writer = StoreWriter(stack: stack, now: { [clock] in clock.withLock { $0 } })
        try await writer.perform(author: .maintenance) { _ = try $0.setHistoryCapacity(.unlimited) }

        let end = Date()
        let start = end.addingTimeInterval(-365 * 24 * 3600)
        let span = end.timeIntervalSince(start)

        var imageItemID: String?
        var longTextItemID: String?
        var historyIDs: [ItemID] = []
        historyIDs.reserveCapacity(options.count)

        var index = 0
        while index < options.count {
            let batchEnd = min(index + options.batchSize, options.count)
            var batch: [NewItem] = []
            for position in index..<batchEnd {
                let timestamp = start.addingTimeInterval(span * (Double(position) + 0.5) / Double(options.count))
                batch.append(makeItem(position: position, timestamp: timestamp))
            }
            let items = batch
            let batchStart = items[0].timestamp
            clock.withLock { $0 = batchStart }
            let ids = try await writer.perform(author: .capture) { context in
                try autoreleasepool {
                    let scratch = try context.createPinboard(name: "scratch", color: .gray)
                    let ids = try items.map { item in
                        let id = try context.create(item, in: scratch)
                        try context.touch(id, at: item.timestamp)
                        return id
                    }
                    try context.deleteList(scratch)
                    return ids
                }
            }
            for (offset, item) in batch.enumerated() {
                if imageItemID == nil, item.type == .image, index + offset > options.count / 2 { imageItemID = ids[offset].rawValue }
                if longTextItemID == nil, item.type == .text, item.pasteboardItems[0].dataByType.values.first.map({ $0.count > 50_000 }) == true,
                   index + offset > options.count / 2 {
                    longTextItemID = ids[offset].rawValue
                }
            }
            historyIDs.append(contentsOf: ids)
            index = batchEnd
            if index % 20_000 == 0 || index == options.count {
                let elapsed = (ContinuousClock.now - started).milliseconds / 1000
                FileHandle.standardError.write(Data("  generated \(index)/\(options.count) in \(Int(elapsed)) s\n".utf8))
            }
        }

        // Pinboards: some items of the history pinned, and a few that live on a pinboard only.
        clock.withLock { $0 = end }
        var pinboardIDs: [String] = []
        for board in 0..<options.pinboardCount {
            var pinned: [ItemID] = []
            for _ in 0..<(options.pinnedFromHistory / options.pinboardCount) {
                pinned.append(historyIDs[Int(random.next() % UInt64(historyIDs.count))])
            }
            let onlyHere = (0..<(options.pinboardOnly / options.pinboardCount)).map { offset in
                makeItem(position: options.count + board * 1_000 + offset, timestamp: end)
            }
            let id = try await writer.perform(author: .user) { [pinned, onlyHere] context in
                let pinboard = try context.createPinboard(name: "Board \(board + 1)", color: .blue)
                try context.pin(pinned, to: pinboard)
                for item in onlyHere {
                    _ = try context.create(item, in: pinboard)
                }
                return pinboard
            }
            pinboardIDs.append(id.rawValue)
        }

        let manifest = Manifest(
            count: options.count,
            seed: options.seed,
            pinboardIDs: pinboardIDs,
            middleItemChecksum: Self.checksum(position: options.count / 2),
            imageItemID: imageItemID ?? historyIDs[historyIDs.count / 2].rawValue,
            longTextItemID: longTextItemID ?? historyIDs[historyIDs.count / 2].rawValue,
            generationSeconds: (ContinuousClock.now - started).milliseconds / 1000,
            generatedAt: end
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(manifest).write(to: directory.appending(path: "manifest.json"))
        return manifest
    }

    static func checksum(position: Int) -> String {
        "stress-\(position)"
    }

    // MARK: - Items

    private func makeItem(position: Int, timestamp: Date) -> NewItem {
        let roll = Double(random.next() % 10_000) / 10_000
        let application = applications[Int(random.next() % UInt64(applications.count))]
        let checksum = Self.checksum(position: position)
        switch roll {
        case ..<0.70:
            return text(words(count: 2 + Int(random.next() % 40), tag: position), checksum: checksum, timestamp: timestamp, application: application)
        case ..<0.85:
            let length = 10_000 + Int(random.next() % 190_000)
            return text(slice(length: length, tag: position), checksum: checksum, timestamp: timestamp, application: application)
        case ..<0.95:
            let image = images[Int(random.next() % UInt64(images.count))]
            return NewItem(
                type: .image,
                checksum: checksum,
                preview: .image(ImagePreview(width: image.width, height: image.height, byteCount: image.png.count, thumbnailData: image.thumbnail)),
                pasteboardItems: [PasteboardItemSnapshot(types: ["public.png"], dataByType: ["public.png": image.png])],
                sourceApplication: application,
                timestamp: timestamp
            )
        case ..<0.97:
            let url = URL(string: "https://example.com/stress/\(position)/\(words(count: 3, tag: position).replacingOccurrences(of: " ", with: "-"))")!
            return NewItem(
                type: .link,
                checksum: checksum,
                preview: .link(LinkPreview(url: url, title: "Page \(position)")),
                pasteboardItems: [PasteboardItemSnapshot(
                    types: ["public.url", "public.utf8-plain-text"],
                    dataByType: ["public.url": url.dataRepresentation, "public.utf8-plain-text": Data(url.absoluteString.utf8)]
                )],
                sourceApplication: application,
                timestamp: timestamp
            )
        case ..<0.99:
            let path = "/Users/stress/Documents/file-\(position).pdf"
            return NewItem(
                type: .files,
                checksum: checksum,
                preview: .files(FilesPreview(paths: [path], totalByteCount: Int64(random.next() % 10_000_000))),
                pasteboardItems: [PasteboardItemSnapshot(types: ["public.file-url"], dataByType: ["public.file-url": Data("file://\(path)".utf8)])],
                sourceApplication: application,
                timestamp: timestamp
            )
        default:
            let code = random.next() & 0xFF_FF_FF
            let hex = String(format: "#%06X", code)
            return NewItem(
                type: .color,
                checksum: checksum,
                preview: .color(ColorPreview(colorCode: code)),
                pasteboardItems: [PasteboardItemSnapshot(types: ["public.utf8-plain-text"], dataByType: ["public.utf8-plain-text": Data(hex.utf8)])],
                sourceApplication: application,
                timestamp: timestamp
            )
        }
    }

    private func text(_ string: String, checksum: String, timestamp: Date, application: SourceApplication) -> NewItem {
        let utf16 = string.utf16
        let preview = utf16.count > 500 ? String(string.prefix(500)) : string
        return NewItem(
            type: .text,
            checksum: checksum,
            preview: .text(TextPreview(text: preview, characterCount: utf16.count)),
            pasteboardItems: [PasteboardItemSnapshot(types: ["public.utf8-plain-text"], dataByType: ["public.utf8-plain-text": Data(string.utf8)])],
            sourceApplication: application,
            timestamp: timestamp
        )
    }

    private static let vocabulary = [
        "the", "quick", "brown", "fox", "jumps", "over", "lazy", "dog", "copy", "paste", "history", "pinboard",
        "swift", "store", "item", "query", "index", "token", "meeting", "invoice", "address", "password", "note",
        "draft", "release", "build", "commit", "review", "design", "layout", "number", "street", "city", "email",
    ]

    private func words(count: Int, tag: Int) -> String {
        var words = (0..<count).map { _ in Self.vocabulary[Int(random.next() % UInt64(Self.vocabulary.count))] }
        words.append("#\(tag)")
        return words.joined(separator: " ")
    }

    private func slice(length: Int, tag: Int) -> String {
        let utf8 = corpus.utf8
        let maxStart = max(utf8.count - length, 0)
        let start = Int(random.next() % UInt64(maxStart + 1))
        let lower = utf8.index(utf8.startIndex, offsetBy: start)
        let upper = utf8.index(lower, offsetBy: min(length, utf8.count - start))
        return "#\(tag)\n" + (String(utf8[lower..<upper]) ?? "")
    }

    private static func corpus(byteCount: Int, random: inout SplitMix64) -> String {
        var text = ""
        text.reserveCapacity(byteCount)
        while text.utf8.count < byteCount {
            text += vocabulary[Int(random.next() % UInt64(vocabulary.count))]
            text += random.next() % 12 == 0 ? ".\n" : " "
        }
        return text
    }
}

/// One image of the pool every image item draws from: a PNG of a given weight and the JPEG
/// thumbnail the card would show.
struct ImageSample {
    var width: Int
    var height: Int
    var png: Data
    var thumbnail: Data

    /// Weights spread evenly over 0.2–5 MB (times `scale`).
    static func pool(count: Int, scale: Double, random: inout SplitMix64) -> [ImageSample] {
        (0..<count).map { index in
            let targetBytes = (200_000 + Double(index) / Double(count - 1) * 4_800_000) * scale
            // Noise does not compress: about four bytes a pixel.
            let side = max(Int((targetBytes / 4).squareRoot()), 8)
            let png = png(width: side, height: side, noise: true, random: &random)
            let thumbnail = jpeg(width: 256, height: 256)
            return ImageSample(width: side, height: side, png: png, thumbnail: thumbnail)
        }
    }

    static func png(width: Int, height: Int, noise: Bool, random: inout SplitMix64) -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for offset in stride(from: 0, to: pixels.count, by: 8) {
            let value = noise ? random.next() : UInt64(offset / 4 % 255) * 0x0101_0101_0101_0101
            for byte in 0..<min(8, pixels.count - offset) {
                pixels[offset + byte] = UInt8(truncatingIfNeeded: value >> (byte * 8))
            }
        }
        for alpha in stride(from: 3, to: pixels.count, by: 4) { pixels[alpha] = 255 }
        return encode(pixels: pixels, width: width, height: height, type: .png)
    }

    static func jpeg(width: Int, height: Int) -> Data {
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                pixels[offset] = UInt8(x % 256)
                pixels[offset + 1] = UInt8(y % 256)
                pixels[offset + 2] = 128
                pixels[offset + 3] = 255
            }
        }
        return encode(pixels: pixels, width: width, height: height, type: .jpeg)
    }

    private static func encode(pixels: [UInt8], width: Int, height: Int, type: UTType) -> Data {
        let data = NSMutableData()
        let provider = CGDataProvider(data: Data(pixels) as CFData)!
        let image = CGImage(
            width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue),
            provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
        )!
        let destination = CGImageDestinationCreateWithData(data, type.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.7] as CFDictionary)
        CGImageDestinationFinalize(destination)
        return data as Data
    }
}

/// A small, fast, seedable generator, so that two runs build the same store.
struct SplitMix64 {
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
