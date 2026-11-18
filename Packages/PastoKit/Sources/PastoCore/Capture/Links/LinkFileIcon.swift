import AppKit
import ImageIO
import UniformTypeIdentifiers

/// The icon of a link to a file — a PDF, a text, an image — as Link Presentation gives it: the
/// system's icon for the kind of file, 64 × 64 pixels (as of macOS 27.2).
enum LinkFileIcon {
    static let pixelSide = 64

    /// A PNG of the icon for the file `url` names, of type `mimeType` when the response says.
    static func png(for url: URL, mimeType: String?) -> Data? {
        let type = mimeType.flatMap { UTType(mimeType: $0) }
            ?? UTType(filenameExtension: url.pathExtension)
            ?? .data
        let icon = NSWorkspace.shared.icon(for: type)
        var rect = CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide)
        guard let image = icon.cgImage(forProposedRect: &rect, context: nil, hints: nil),
              let context = CGContext(
                  data: nil, width: pixelSide, height: pixelSide, bitsPerComponent: 8, bytesPerRow: 0,
                  space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: pixelSide, height: pixelSide))
        guard let drawn = context.makeImage() else { return nil }
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(output, UTType.png.identifier as CFString, 1, nil) else { return nil }
        CGImageDestinationAddImage(destination, drawn, nil)
        return CGImageDestinationFinalize(destination) ? output as Data : nil
    }

    /// The name of the file `url` names, without its extension, as Link Presentation titles a
    /// link to a file; `nil` when the address names none.
    static func title(of url: URL) -> String? {
        let name = url.deletingPathExtension().lastPathComponent
        return name.isEmpty || name == "/" ? nil : name
    }
}
