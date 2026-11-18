import Foundation
import UniformTypeIdentifiers

/// The constants of the restore path, in one place.
enum RestoreMetrics {
    // MARK: - Composition

    /// A type whose identifier contains one of these is not written back. The one entry keeps
    /// OLE references captured from Office off the pasteboard.
    static let bannedTypes = ["com.microsoft.ole.source"]

    /// The types that can give an element's text, in the order they are tried.
    static let stringTypes = ["public.plain-text", "public.utf8-plain-text", "public.text", "public.url"]

    /// The only type of an element in its plain-text form and of the merged element when it is
    /// plain; also the last content type of the merged element with formatting.
    static let plainTextType = "public.utf8-plain-text"

    /// The first type of the merged element when it keeps its formatting.
    static let rtfType = "public.rtf"

    /// The merged element with its formatting also carries its text in UTF-16, with a byte-order
    /// mark.
    static let externalUTF16PlainTextType = "public.utf16-external-plain-text"

    /// The types an element's rich text is read from when items are merged, in the order they
    /// are tried. All but the last hold RTFD.
    static let richTextTypes = ["com.apple.flat-rtfd", "com.apple.rtfd", rtfType]

    /// What goes between the pieces of the merged element.
    static let mergeSeparator = "\n"

    // MARK: - Temporary image copies

    /// The image types a copy can be made from, in the order they are tried.
    static let imageTypes: [UTType] = [.png, .jpeg, .heic, .tiff]

    /// The type that points at the temporary copy.
    static let fileURLType = "public.file-url"

    /// The folder of the copies, inside the temporary directory.
    static let temporaryImagesDirectoryName = "images"

    /// Names a copy whose item has no source application: the app's own name.
    static let ownApplicationName = "Pasto"

    /// `yyyy-MM-dd HH.mm.ss`: the date in the name of a copy.
    static let temporaryImageDateFormat: Date.FormatString =
        "\(year: .padded(4))-\(month: .twoDigits)-\(day: .twoDigits) \(hour: .twoDigits(clock: .twentyFourHour, hourCycle: .zeroBased)).\(minute: .twoDigits).\(second: .twoDigits)"

    /// A TIFF this large or larger is written as PNG without row filters: same pixels, about
    /// half the encoding time on the main thread (300 MB: 8.2 → 4.6 s), a larger file.
    static let unfilteredPNGThreshold = 64 * 1024 * 1024

    /// `IMAGEIO_PNG_FILTER_NONE`, for `kCGImagePropertyPNGCompressionFilter`.
    static let pngNoFilter = 0x08

    /// A TIFF this large or larger has its PNG copy encoded after the pasteboard is written, its
    /// file URL going on as a promise: from here the encoding takes a noticeable part of a second.
    static let deferredConversionThreshold = 16 * 1024 * 1024

    /// How long a copy lives: the clean-up deletes the ones created before that (86,400 s).
    static let temporaryImageLifetime: TimeInterval = 24 * 60 * 60

    // MARK: - Single image file

    /// Present in the environment of a sandboxed process, which gets no temporary copy for an
    /// image that is restored on its own.
    static let sandboxContainerEnvironmentKey = "APP_SANDBOX_CONTAINER_ID"
}
