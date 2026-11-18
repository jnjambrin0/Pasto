import Foundation
import ImageIO
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// The first page of a PDF a link leads to, as Link Presentation shows it: 1024 pixels on its
/// longest side. Quick Look draws it out of the process, as it does
/// file thumbnails (`FileSummary`): the app never parses a downloaded document itself. The
/// document waits in a file of its own — `0600`, in a folder of its own, `0700` — that is
/// deleted as soon as the thumbnail is made.
enum LinkDocumentThumbnail {
    static let pixelSide: CGFloat = 1024
    /// The temporary folders' names start with this.
    static let folderPrefix = "link-document-"

    /// A PNG of the first page of the PDF in `data`; `nil` when Quick Look cannot draw it.
    static func png(ofPDF data: Data) async -> Data? {
        let folder = URL.temporaryDirectory.appending(path: folderPrefix + UUID().uuidString, directoryHint: .isDirectory)
        let files = FileManager.default
        guard (try? files.createDirectory(at: folder, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])) != nil else {
            return nil
        }
        defer { try? files.removeItem(at: folder) }
        let file = folder.appending(path: "document.pdf")
        guard files.createFile(atPath: file.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return nil }

        let request = QLThumbnailGenerator.Request(
            fileAt: file,
            size: CGSize(width: pixelSide, height: pixelSide),
            scale: 1,
            representationTypes: .thumbnail
        )
        guard let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, thumbnail.cgImage, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }
}
