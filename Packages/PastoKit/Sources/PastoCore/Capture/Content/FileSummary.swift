import AppKit
import QuickLookThumbnailing

/// What a files preview stores about its first file.
enum FileSummary {
    /// Side, in pixels, of a Quick Look thumbnail.
    static let thumbnailSide: CGFloat = 256
    /// Side, in points, of the Finder icon used when there is no thumbnail.
    static let iconSide: CGFloat = 128

    /// The file's size as the file system reports it; 0 when it cannot be read. A folder is
    /// not walked.
    static func byteCount(ofFileAt path: String) -> Int64 {
        let values = try? URL(fileURLWithPath: path).resourceValues(forKeys: [.totalFileSizeKey])
        return Int64(values?.totalFileSize ?? 0)
    }

    /// A PNG of the file's Quick Look thumbnail, drawn as an icon, or else of its Finder icon.
    static func thumbnailData(ofFileAt path: String) async -> Data? {
        let request = QLThumbnailGenerator.Request(
            fileAt: URL(fileURLWithPath: path),
            size: CGSize(width: thumbnailSide, height: thumbnailSide),
            scale: 1,
            representationTypes: .thumbnail
        )
        request.iconMode = true
        if let thumbnail = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            return pngData(of: thumbnail.cgImage)
        }

        let icon = NSWorkspace.shared.icon(forFile: path)
        var rect = CGRect(x: 0, y: 0, width: iconSide, height: iconSide)
        return icon.cgImage(forProposedRect: &rect, context: nil, hints: nil).flatMap(pngData)
    }

    private static func pngData(of image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }
}
