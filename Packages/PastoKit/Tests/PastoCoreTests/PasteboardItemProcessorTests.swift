import CoreGraphics
import Foundation
import ImageIO
@testable import PastoCore
import Testing
import UniformTypeIdentifiers

/// The file a restored image gets, and when it gets one. Everything is written under a folder of
/// the test's own.
struct PasteboardItemProcessorTests {
    private let folder = TemporaryFolder()
    private let gmt = TimeZone(identifier: "GMT")!
    private let cleanups = CleanupJobs()

    /// 2026-01-02 03:04:05 GMT: when the items of these tests were copied.
    private var copied: Date {
        DateComponents(calendar: Calendar(identifier: .gregorian), timeZone: gmt, year: 2026, month: 1, day: 2, hour: 3, minute: 4, second: 5).date!
    }

    /// The clock of the clean-up: a week after the copy, and before the real date at which the
    /// tests write their files.
    private var now: Date { copied.addingTimeInterval(7 * 86_400) }

    private func makeProcessor(
        includesSingleImageFile: Bool = true,
        calendar: Calendar = Calendar(identifier: .gregorian)
    ) -> PasteboardItemProcessor {
        PasteboardItemProcessor(
            includesSingleImageFile: includesSingleImageFile,
            directory: TemporaryImageDirectory(temporaryDirectory: folder.url),
            now: { [now] in now },
            locale: Locale(identifier: "en_US_POSIX"),
            calendar: calendar,
            timeZone: gmt,
            scheduleCleanup: { [cleanups] in cleanups.jobs.append($0) }
        )
    }

    private func image(_ elements: [PasteboardItemSnapshot], from source: SourceApplication? = .safari) -> RestorableItem {
        .make(.image, elements, from: source, at: copied)
    }

    private let png = PasteboardItemSnapshot(["public.png": Data("png".utf8)])

    /// The file an element points at, and what it holds.
    private func fileCopy(of element: PasteboardItemSnapshot) throws -> (url: URL, data: Data) {
        let string = try #require(element.dataByType["public.file-url"].flatMap { String(data: $0, encoding: .utf8) })
        let url = try #require(URL(string: string))
        return (url, try Data(contentsOf: url))
    }

    // MARK: - When it acts

    @Test(arguments: [ItemType.text, .link, .files, .color, .unknown])
    func itemsThatAreNotImagesGoThroughUntouched(type: ItemType) {
        var processor = makeProcessor()

        let processed = processor.process(.make(type, [png, png], at: copied))

        #expect(processed == [png, png])
        #expect(folder.imageFilenames.isEmpty)
        #expect(cleanups.jobs.isEmpty)
    }

    @Test func anImageWithOneElementOnlyGetsAFileWhenAsked() throws {
        var withoutFlag = makeProcessor(includesSingleImageFile: false)
        #expect(withoutFlag.process(image([png])) == [png])
        #expect(folder.imageFilenames.isEmpty)

        var withFlag = makeProcessor(includesSingleImageFile: true)
        let processed = withFlag.process(image([png]))
        #expect(processed.first?.types == ["public.png", "public.file-url"])
        #expect(folder.imageFilenames.count == 1)
    }

    @Test func anImageWithSeveralElementsAlwaysGetsFiles() {
        var processor = makeProcessor(includesSingleImageFile: false)

        let processed = processor.process(image([png, png]))

        #expect(processed.map(\.types) == [["public.png", "public.file-url"], ["public.png", "public.file-url"]])
        #expect(folder.imageFilenames.count == 2)
    }

    // MARK: - Which data is copied

    @Test func theCopyIsMadeFromTheFirstRepresentationInPasteboardOrder() throws {
        // Declared in the opposite order, and none of it decodable: only the type decides.
        var representations: [(type: String, extension: String)] = [
            ("public.tiff", "tiff"), ("public.heic", "heic"), ("public.jpeg", "jpeg"), ("public.png", "png"),
        ]

        while let preferred = representations.last {
            var processor = makeProcessor()
            let element = PasteboardItemSnapshot(
                types: representations.map(\.type),
                dataByType: Dictionary(uniqueKeysWithValues: representations.map { ($0.type, Data($0.type.utf8)) })
            )

            let copy = try fileCopy(of: try #require(processor.process(image([element])).first))

            #expect(copy.url.pathExtension == preferred.extension)
            #expect(copy.data == Data(preferred.type.utf8))
            representations.removeLast()
        }
    }

    @Test func aTIFFWithOneImageIsWrittenAsPNG() throws {
        let tiff = TestImage.tiff(pages: 1)
        var processor = makeProcessor()

        let processed = try #require(processor.process(image([PasteboardItemSnapshot(["public.tiff": tiff])])).first)

        // The pasteboard item keeps its TIFF: only the file is converted.
        #expect(processed.types == ["public.tiff", "public.file-url"])
        #expect(processed.dataByType["public.tiff"] == tiff)
        let copy = try fileCopy(of: processed)
        #expect(copy.url.pathExtension == "png")
        #expect(copy.data.prefix(8) == TestImage.pngSignature)
    }

    @Test func aLargeTIFFBecomesTheSamePixelsWithoutPNGFilters() throws {
        let image = TestImage.make(width: 64, height: 48) { x, y in
            TestImage.Pixel(red: UInt8(x * 4), green: UInt8(y * 5), blue: UInt8((x + y) % 256))
        }
        let output = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(output, UTType.tiff.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        #expect(CGImageDestinationFinalize(destination))
        let tiff = output as Data
        let filtered = try #require(ImageRepresentation.pngData(fromSingleImageTIFF: tiff, unfiltered: false))
        let unfiltered = try #require(ImageRepresentation.pngData(fromSingleImageTIFF: tiff, unfiltered: true))

        func pixels(_ png: Data) throws -> Data {
            let source = try #require(CGImageSourceCreateWithData(png as CFData, nil))
            let image = try #require(CGImageSourceCreateImageAtIndex(source, 0, nil))
            return try #require(image.dataProvider?.data as Data?)
        }
        #expect(try pixels(filtered) == pixels(unfiltered))
        #expect(filtered != unfiltered)
    }

    @Test func aTIFFWithSeveralImagesOrThatCannotBeReadStaysATIFF() throws {
        for tiff in [TestImage.tiff(pages: 2), Data("not an image".utf8)] {
            var processor = makeProcessor()

            let copy = try fileCopy(of: try #require(processor.process(image([PasteboardItemSnapshot(["public.tiff": tiff])])).first))

            #expect(copy.url.pathExtension == "tiff")
            #expect(copy.data == tiff)
        }
    }

    @Test func anElementWithoutImageDataIsLeftAsItIs() {
        let caption = PasteboardItemSnapshot.plainText("caption")
        var processor = makeProcessor()

        let processed = processor.process(image([caption, png]))

        #expect(processed.first == caption)
        #expect(processed.last?.types == ["public.png", "public.file-url"])
    }

    // MARK: - Where it is copied

    @Test func theFileIsNamedAfterTheSourceApplicationAndTheDateOfTheItem() throws {
        var processor = makeProcessor()

        let processed = try #require(processor.process(image([png])).first)

        let expected = folder.images.appending(path: "Safari 2026-01-02 03.04.05.png")
        #expect(processed.dataByType["public.file-url"] == Data(expected.absoluteString.utf8))
        #expect(try Data(contentsOf: expected) == Data("png".utf8))
    }

    @Test func theDateInTheNameIsInTheUsersCalendar() {
        var processor = makeProcessor(calendar: Calendar(identifier: .buddhist))

        _ = processor.process(image([png]))

        #expect(folder.imageFilenames == ["Safari 2569-01-02 03.04.05.png"])
    }

    @Test func anItemWithoutSourceApplicationIsNamedAfterPasto() {
        var processor = makeProcessor()

        _ = processor.process(image([png], from: nil))

        #expect(folder.imageFilenames == ["Pasto 2026-01-02 03.04.05.png"])
    }

    @Test func theFilesOfOneRestoreNeverShareAName() {
        var processor = makeProcessor()

        // Two elements of one image, then another image copied from the same application in the same second.
        _ = processor.process(image([png, png]))
        _ = processor.process(image([png]))

        #expect(folder.imageFilenames == [
            "Safari 2026-01-02 03.04.05 2.png",
            "Safari 2026-01-02 03.04.05 3.png",
            "Safari 2026-01-02 03.04.05.png",
        ])
    }

    @Test func aPathSeparatorInTheApplicationNameDoesNotLeaveTheFolder() {
        var processor = makeProcessor()

        _ = processor.process(image([png], from: SourceApplication(bundleIdentifier: "x", name: "../Up/Down")))

        #expect(folder.imageFilenames == ["..:Up:Down 2026-01-02 03.04.05.png"])
    }

    @Test func whenTheFileCannotBeWrittenTheElementIsRestoredWithoutIt() throws {
        // A file where the folder should be.
        try Data().write(to: folder.url.appending(path: "images"))
        var processor = makeProcessor()

        #expect(processor.process(image([png])) == [png])
    }

    // MARK: - Clean-up

    @Test func theCleanupDeletesTheCopiesOlderThanADayAndRunsLater() throws {
        let expired = try makeFile(named: "expired.png", created: now.addingTimeInterval(-86_401))
        let recent = try makeFile(named: "recent.png", created: now.addingTimeInterval(-86_399))
        var processor = makeProcessor()

        _ = processor.process(image([png]))

        // Scheduled once for the item, and not run as part of processing it.
        let cleanup = try #require(cleanups.jobs.first)
        #expect(cleanups.jobs.count == 1)
        #expect(FileManager.default.fileExists(atPath: expired.path))

        cleanup()

        #expect(!FileManager.default.fileExists(atPath: expired.path))
        #expect(FileManager.default.fileExists(atPath: recent.path))
        #expect(folder.imageFilenames == ["Safari 2026-01-02 03.04.05.png", "recent.png"])
    }

    @Test func theFolderAndTheCopiesAreTheUsersAlone() throws {
        // A folder left by an earlier version, readable by everyone.
        try FileManager.default.createDirectory(at: folder.images, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        var processor = makeProcessor()

        let (copy, _) = try fileCopy(of: try #require(processor.process(image([png])).first))

        #expect(try permissions(of: folder.images) == 0o700)
        #expect(try permissions(of: copy) == 0o600)
    }

    @Test func removingTheCopiesDeletesThemAllWhateverTheirAge() throws {
        _ = try makeFile(named: "expired.png", created: now.addingTimeInterval(-86_401))
        _ = try makeFile(named: "recent.png", created: Date())

        ItemRestorer.removeTemporaryImageCopies(temporaryDirectory: folder.url)

        #expect(!FileManager.default.fileExists(atPath: folder.images.path))
        // Nothing to remove is not an error.
        ItemRestorer.removeTemporaryImageCopies(temporaryDirectory: folder.url)
    }

    private func permissions(of url: URL) throws -> Int {
        try #require(FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int)
    }

    private func makeFile(named name: String, created: Date) throws -> URL {
        try FileManager.default.createDirectory(at: folder.images, withIntermediateDirectories: true)
        let file = folder.images.appending(path: name)
        try Data("old".utf8).write(to: file)
        try FileManager.default.setAttributes([.creationDate: created], ofItemAtPath: file.path)
        return file
    }

    // MARK: - A lone image

    @Test func aLoneImageGetsAFileUnlessTheProcessIsSandboxed() {
        #expect(PasteboardItemProcessor.includesSingleImageFile(environment: [:]))
        #expect(PasteboardItemProcessor.includesSingleImageFile(environment: ["PATH": "/usr/bin"]))
        #expect(!PasteboardItemProcessor.includesSingleImageFile(environment: ["APP_SANDBOX_CONTAINER_ID": "jnjambrino.Pasto"]))
    }
}

/// The clean-ups a processor scheduled, kept instead of run.
private final class CleanupJobs {
    var jobs: [@Sendable () -> Void] = []
}
