import AppKit

/// How an application's icon is stored and looked at.
enum ApplicationIcon {
    /// The size, in points, at which the icon is rendered and stored.
    static let size = CGSize(width: 128, height: 128)

    /// The stored form of the icon: a PNG of the rendered image, tagged with its size in points
    /// and without touching its pixels (128 or 256 on a side, whichever AppKit rendered).
    static func pngData(of icon: CGImage) -> Data? {
        let representation = NSBitmapImageRep(cgImage: icon)
        representation.size = size
        return representation.representation(using: .png, properties: [:])
    }

    /// The bitmap the colour is computed from: the icon at one pixel per point, or at its own
    /// size if it is smaller than that.
    static func colorBitmap(of icon: CGImage) -> RGBABitmap? {
        RGBABitmap(
            drawing: icon,
            width: min(Int(size.width), icon.width),
            height: min(Int(size.height), icon.height)
        )
    }
}
