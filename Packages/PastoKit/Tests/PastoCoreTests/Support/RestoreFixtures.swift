import CoreGraphics
import Foundation
import ImageIO
import os
@testable import PastoCore
import UniformTypeIdentifiers

// MARK: - Values

extension PasteboardItemSnapshot {
    /// A pasteboard item that only holds UTF-8 plain text.
    static func plainText(_ string: String) -> PasteboardItemSnapshot {
        PasteboardItemSnapshot(["public.utf8-plain-text": Data(string.utf8)])
    }

    /// The item as a restore leaves it: followed by the source marker and the own-write marker.
    func signed(from bundleIdentifier: String = "") -> PasteboardItemSnapshot {
        var signed = self
        signed.types += [PasteboardMarker.source, PasteboardMarker.ownWrite]
        signed.dataByType[PasteboardMarker.source] = Data(bundleIdentifier.utf8)
        signed.dataByType[PasteboardMarker.ownWrite] = Data()
        return signed
    }
}

extension RestorableItem {
    static func make(
        _ type: ItemType,
        _ pasteboardItems: [PasteboardItemSnapshot],
        from sourceApplication: SourceApplication? = nil,
        at timestamp: Date = .second(0)
    ) -> RestorableItem {
        RestorableItem(type: type, pasteboardItems: pasteboardItems, sourceApplication: sourceApplication, timestamp: timestamp)
    }
}

extension SourceApplication {
    static let safari = SourceApplication(bundleIdentifier: "com.apple.Safari", name: "Safari")
}

extension TestImage {
    /// A TIFF with that many 2×2 images in it.
    static func tiff(pages: Int) -> Data {
        let context = CGContext(
            data: nil, width: 2, height: 2, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        let image = context.makeImage()!
        let output = NSMutableData()
        let destination = CGImageDestinationCreateWithData(output, UTType.tiff.identifier as CFString, pages, nil)!
        for _ in 0..<pages {
            CGImageDestinationAddImage(destination, image, nil)
        }
        precondition(CGImageDestinationFinalize(destination))
        return output as Data
    }

    /// The eight bytes every PNG file starts with.
    static let pngSignature = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
}

// MARK: - Doubles

/// A processor that writes nothing: every item keeps its stored pasteboard items.
struct PassThroughProcessor: PasteboardItemProcessing {
    func process(_ item: RestorableItem) -> [PasteboardItemSnapshot] {
        item.pasteboardItems
    }
}

/// Stands in for the general pasteboard: remembers what was written instead of writing it.
final class RecordingPasteboard: PasteboardWriting {
    private struct State {
        var writes: [[PasteboardItemSnapshot]] = []
        var changeCount = 100
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var writes: [[PasteboardItemSnapshot]] { state.withLock { $0.writes } }
    var changeCount: Int { state.withLock { $0.changeCount } }

    func write(_ items: [PasteboardItemSnapshot]) -> Int {
        state.withLock { state in
            state.writes.append(items)
            state.changeCount += 1
            return state.changeCount
        }
    }
}

/// A clock that advances one second every time it is read, so that the order of the readings
/// shows in what they stamped.
final class TickingClock: Sendable {
    private let next: OSAllocatedUnfairLock<Date>

    init(startingAt date: Date) {
        next = OSAllocatedUnfairLock(initialState: date)
    }

    func now() -> Date {
        next.withLock { date in
            defer { date += 1 }
            return date
        }
    }
}

/// A folder of its own for one test, gone when the test ends.
final class TemporaryFolder {
    let url: URL

    init() {
        url = FileManager.default.temporaryDirectory.appending(path: "PastoTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// The folder the temporary image copies go to.
    var images: URL {
        url.appending(path: "images", directoryHint: .isDirectory)
    }

    /// The names of the files in `images`, sorted.
    var imageFilenames: [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? []).sorted()
    }
}
