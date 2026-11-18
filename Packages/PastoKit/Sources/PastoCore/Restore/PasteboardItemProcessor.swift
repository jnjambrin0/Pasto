import Foundation
import os
import PastoFoundation
import UniformTypeIdentifiers

/// Gives restored images a file.
///
/// Many paste targets take a file but not raw image data, so every pasteboard item of an image
/// also gets a copy of the image in the temporary directory and a file URL that points at it.
/// Items of any other type go through untouched.
///
/// One processor serves one restore: it remembers the names it has given out, so that the images
/// of that restore never share a file.
struct PasteboardItemProcessor: PasteboardItemProcessing {
    /// How the clean-up is run: on a background queue, so that listing a folder never delays a paste.
    typealias CleanupScheduler = (_ cleanup: @escaping @Sendable () -> Void) -> Void

    private let includesSingleImageFile: Bool
    /// Whether a large TIFF's PNG copy may be encoded after the pasteboard is written, its file
    /// URL going on as a promise (`PendingImageCopy`).
    private let defersLargeConversions: Bool
    private let directory: TemporaryImageDirectory
    private let now: @Sendable () -> Date
    private let dateStyle: Date.VerbatimFormatStyle
    private let scheduleCleanup: CleanupScheduler
    private let log = Log.logger(.paste)
    /// Without extension, as given out by `unusedName(for:)`.
    private var writtenFilenames: Set<String> = []

    /// - Parameters:
    ///   - includesSingleImageFile: Whether an image with a single pasteboard item gets a copy
    ///     too. An image with several always does.
    ///   - defersLargeConversions: Whether the pasteboard written next takes copies still being
    ///     written (`PasteboardWriting.promisesPendingImageCopies`).
    ///   - now: The clock the clean-up measures the age of the copies with.
    ///   - locale, calendar, timeZone: Those of the date in the file names: the user's.
    init(
        includesSingleImageFile: Bool,
        defersLargeConversions: Bool = false,
        directory: TemporaryImageDirectory,
        now: @escaping @Sendable () -> Date,
        locale: Locale = .current,
        calendar: Calendar = .current,
        timeZone: TimeZone = .current,
        scheduleCleanup: @escaping CleanupScheduler = { DispatchQueue.global(qos: .background).async(execute: $0) }
    ) {
        self.includesSingleImageFile = includesSingleImageFile
        self.defersLargeConversions = defersLargeConversions
        self.directory = directory
        self.now = now
        dateStyle = Date.VerbatimFormatStyle(
            format: RestoreMetrics.temporaryImageDateFormat,
            locale: locale,
            timeZone: timeZone,
            calendar: calendar
        )
        self.scheduleCleanup = scheduleCleanup
    }

    /// Whether an image restored on its own gets a temporary file: always, except in a
    /// sandboxed process, whose temporary directory other applications cannot read.
    static func includesSingleImageFile(environment: [String: String]) -> Bool {
        environment[RestoreMetrics.sandboxContainerEnvironmentKey] == nil
    }

    mutating func process(_ item: RestorableItem) -> [PasteboardItemSnapshot] {
        guard item.type == .image, includesSingleImageFile || item.pasteboardItems.count >= 2 else {
            return item.pasteboardItems
        }

        let name = Self.sanitizedFilename("\(item.sourceApplication?.name ?? RestoreMetrics.ownApplicationName) \(item.timestamp.formatted(dateStyle))")
        let elements = item.pasteboardItems.map { addingFileCopy(to: $0, named: name) }

        scheduleCleanup { [directory, now] in
            directory.removeFiles(createdBefore: now().addingTimeInterval(-RestoreMetrics.temporaryImageLifetime))
        }
        return elements
    }

    /// `element` with the URL of a copy of its image, or as it is when it holds no image or the
    /// copy cannot be written: the image data itself is still pasted.
    private mutating func addingFileCopy(to element: PasteboardItemSnapshot, named name: String) -> PasteboardItemSnapshot {
        guard let source = ImageRepresentation(of: element) else { return element }
        if defersLargeConversions, source.convertsToPNG, source.data.count >= RestoreMetrics.deferredConversionThreshold {
            return addingPendingFileCopy(of: source, to: element, named: name)
        }
        let image = source.fileRepresentation

        let name = unusedName(for: name)
        let filename = [name, image.type.preferredFilenameExtension].compactMap { $0 }.joined(separator: ".")
        do {
            let file = try directory.write(image.data, filename: filename)
            writtenFilenames.insert(name)

            var element = element
            element.declareLast(RestoreMetrics.fileURLType, data: Data(file.absoluteString.utf8))
            return element
        } catch {
            log.error("Could not write the temporary copy of an image: \(error)")
            return element
        }
    }

    /// `element` with the URL of a PNG copy of its TIFF that is encoded in the background: the
    /// pasteboard hands the URL over once the file is written (`PendingImageCopy`). Should the
    /// encoding fail, the copy is the TIFF itself, as when it is made at once.
    private mutating func addingPendingFileCopy(
        of source: ImageRepresentation,
        to element: PasteboardItemSnapshot,
        named name: String
    ) -> PasteboardItemSnapshot {
        let name = unusedName(for: name)
        writtenFilenames.insert(name)
        let planned = directory.url.appending(path: "\(name).png", directoryHint: .notDirectory)
        let copy = PendingImageCopy.begin(at: planned) { [directory, log] in
            let image = source.fileRepresentation
            let filename = [name, image.type.preferredFilenameExtension].compactMap { $0 }.joined(separator: ".")
            do {
                return try directory.write(image.data, filename: filename)
            } catch {
                log.error("Could not write the temporary copy of an image: \(error)")
                return nil
            }
        }
        var element = element
        element.declareLast(RestoreMetrics.fileURLType, data: Data(copy.plannedURL.absoluteString.utf8))
        return element
    }

    /// `name`, or `name` followed by a counter when this restore has already written a file of
    /// that name (the pasteboard items of one image share source and date).
    private func unusedName(for name: String) -> String {
        var candidate = name
        var counter = 2
        while writtenFilenames.contains(candidate) {
            candidate = "\(name) \(counter)"
            counter += 1
        }
        return candidate
    }

    /// The name of an application is not under Pasto's control; a path separator in it must not
    /// take the file out of the folder. ":" is what the file system itself stores for a "/" typed
    /// in the Finder.
    private static func sanitizedFilename(_ name: String) -> String {
        name.replacing("/", with: ":")
    }
}
