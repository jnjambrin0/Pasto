import AppKit

/// Turning and encoding the image of an image item. Both work on the image's pixels, so nothing
/// is lost to the screen's scale.
extension NSImage {
    /// The image turned by quarter turns, clockwise when positive. `nil` if it has no bitmap.
    func rotated(byQuarterTurns turns: Int) -> NSImage? {
        guard let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let swapsSides = !turns.isMultiple(of: 2)
        let width = swapsSides ? source.height : source.width
        let height = swapsSides ? source.width : source.height

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        // Core Graphics turns anticlockwise for positive angles.
        context.rotate(by: -CGFloat(turns) * .pi / 2)
        context.draw(source, in: CGRect(
            x: -CGFloat(source.width) / 2,
            y: -CGFloat(source.height) / 2,
            width: CGFloat(source.width),
            height: CGFloat(source.height)
        ))
        guard let rotated = context.makeImage() else { return nil }
        return NSImage(
            cgImage: rotated,
            size: swapsSides ? NSSize(width: size.height, height: size.width) : size
        )
    }

    /// The image as an edit stores it: PNG, or a JPEG when that cannot be made. `nil` when
    /// neither can, in which case nothing is saved.
    var encodedForSaving: ItemContentComposer.EncodedImage? {
        guard let source = cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
        let bitmap = NSBitmapImageRep(cgImage: source)
        if let png = bitmap.representation(using: .png, properties: [:]) {
            return .png(png)
        }
        let quality = [NSBitmapImageRep.PropertyKey.compressionFactor: PreviewMetrics.jpegFallbackQuality]
        return bitmap.representation(using: .jpeg, properties: quality).map { .jpeg($0) }
    }
}
