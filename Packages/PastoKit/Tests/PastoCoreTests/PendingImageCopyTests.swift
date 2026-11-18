import AppKit
import Foundation
@testable @_spi(Benchmarks) import PastoCore
import Testing

/// Pasting a large image that only came as TIFF: its PNG copy is encoded after the pasteboard is
/// written, which holds the copy's file URL as a promise until the file is there.
@Suite(.timeLimit(.minutes(1)))
struct PendingImageCopyTests {
    private let folder = TemporaryFolder()

    private func processor(defers: Bool) -> PasteboardItemProcessor {
        PasteboardItemProcessor(
            includesSingleImageFile: true,
            defersLargeConversions: defers,
            directory: TemporaryImageDirectory(temporaryDirectory: folder.url),
            now: { .second(0) },
            scheduleCleanup: { _ in }
        )
    }

    /// An uncompressed TIFF a little over the threshold.
    private static let largeTIFF = TestImage.encoded(TestImage.solid(.red, width: 2_600, height: 1_700), as: "public.tiff")

    @Test func aLargeTIFFsCopyIsPromisedAndTheFileFollowsAtTheSameAddress() throws {
        #expect(Self.largeTIFF.count >= RestoreMetrics.deferredConversionThreshold)
        var processor = processor(defers: true)
        let element = try #require(processor.process(.make(.image, [PasteboardItemSnapshot(["public.tiff": Self.largeTIFF])], from: .safari)).first)
        let planned = try #require(element.dataByType[RestoreMetrics.fileURLType])
        #expect(element.types.last == RestoreMetrics.fileURLType)

        let writer = NamedPasteboardWriter(name: "jnjambrino.Pasto.tests.\(UUID().uuidString)")
        defer { writer.release() }
        #expect(writer.promisesPendingImageCopies)
        _ = writer.write([element])
        // The writer took the plan: the file URL went on as a promise.
        #expect(PendingImageCopy.take(forURLData: planned) == nil)
        // The TIFF is on the pasteboard at once; reading the file URL waits for the copy.
        #expect(writer.pasteboard.data(forType: NSPasteboard.PasteboardType("public.tiff")) == Self.largeTIFF)
        let provided = try #require(writer.pasteboard.data(forType: NSPasteboard.PasteboardType(RestoreMetrics.fileURLType)))
        #expect(provided == planned)

        let file = try #require(URL(string: String(decoding: provided, as: UTF8.self)))
        #expect(file.pathExtension == "png")
        #expect(try Data(contentsOf: file).prefix(4) == Data([0x89, 0x50, 0x4E, 0x47]))
    }

    @Test func aSmallTIFFOrAPasteboardThatCannotPromiseGetsItsCopyAtOnce() throws {
        let small = TestImage.encoded(TestImage.solid(.red, width: 40, height: 30), as: "public.tiff")
        for (tiff, defers) in [(small, true), (Self.largeTIFF, false)] {
            var processor = processor(defers: defers)
            let element = try #require(processor.process(.make(.image, [PasteboardItemSnapshot(["public.tiff": tiff])])).first)
            let url = try #require(element.dataByType[RestoreMetrics.fileURLType].flatMap { URL(string: String(decoding: $0, as: UTF8.self)) })
            // Written before the item is handed over, and nothing left to take.
            #expect(FileManager.default.fileExists(atPath: url.path(percentEncoded: false)))
            #expect(PendingImageCopy.take(forURLData: Data(url.absoluteString.utf8)) == nil)
        }
    }
}
