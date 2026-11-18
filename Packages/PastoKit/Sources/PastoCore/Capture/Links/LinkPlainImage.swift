import CoreGraphics
import Foundation
import ImageIO

/// Spots an image of a single colour all over: a placeholder, not a picture. Link Presentation
/// gives no image for a page whose image is one (as of macOS 27.2, a plain white or green
/// `og:image` is dropped; a single pixel of another colour is enough to keep it), and does not
/// try the page's next image instead.
enum LinkPlainImage {
    /// Whether every pixel of the image in `data` — already reduced, so at most a few hundred
    /// thousand pixels — is the same.
    static func isPlain(_ data: Data) -> Bool {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              let bitmap = RGBABitmap(drawing: image, width: image.width, height: image.height)
        else { return false }
        return bitmap.bytes.withUnsafeBufferPointer { bytes in
            stride(from: 4, to: bytes.count, by: 4).allSatisfy { index in
                bytes[index] == bytes[0] && bytes[index + 1] == bytes[1]
                    && bytes[index + 2] == bytes[2] && bytes[index + 3] == bytes[3]
            }
        }
    }
}
