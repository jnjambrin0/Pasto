import CoreGraphics
import ImageIO

/// How capture shrinks an image into a box given in points: the box is compared with the
/// image's size in points, the image is only ever reduced, keeping its proportions, and the
/// result is rendered for a 2× display — never with more pixels than the image has.
enum ImageFitting {
    static let pixelsPerPoint: CGFloat = 2

    /// The size in points of an image whose ImageIO properties are `properties`: its pixels at
    /// the resolution it declares, or at 72 dots per inch when it declares none.
    static func pointSize(pixelWidth: Int, pixelHeight: Int, properties: [CFString: Any]) -> CGSize {
        CGSize(
            width: points(pixelWidth, dotsPerInch: properties[kCGImagePropertyDPIWidth] as? Double),
            height: points(pixelHeight, dotsPerInch: properties[kCGImagePropertyDPIHeight] as? Double)
        )
    }

    /// How many pixels an image of `pixelSize` and `pointSize` gets once fitted into `box`.
    static func pixelSize(fitting box: CGSize, pixelSize: CGSize, pointSize: CGSize) -> CGSize {
        let scale = min(box.width / pointSize.width, box.height / pointSize.height)
        guard scale < 1 else { return pixelSize }
        return CGSize(
            width: max(1, min(pixelSize.width, (pointSize.width * scale * pixelsPerPoint).rounded())),
            height: max(1, min(pixelSize.height, (pointSize.height * scale * pixelsPerPoint).rounded()))
        )
    }

    private static func points(_ pixels: Int, dotsPerInch: Double?) -> CGFloat {
        guard let dotsPerInch, dotsPerInch > 0 else { return CGFloat(pixels) }
        return CGFloat(pixels) * 72 / dotsPerInch
    }
}
