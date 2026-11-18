import AppKit
import CoreText
import UniformTypeIdentifiers

/// Images drawn at run time for the sample cards, so the tool carries no bitmap. The two image
/// items match the ones `pastoprobe seed` puts on the clipboard.
enum SampleImages {
    /// The 640 × 400 gradient with a label of the seeded `image-gradient` item.
    static let gradient = png(width: 640, height: 400) { context in
        drawGradient(in: context, width: 640, height: 400)
        drawLabel("ProbeKit seed · 640 × 400", in: context, at: CGPoint(x: 32, y: 40), size: 36)
    }

    /// The 96 × 96 translucent badge of the seeded `image-transparent` item.
    static let transparentBadge = png(width: 96, height: 96) { context in
        context.setFillColor(red: 0.204, green: 0.78, blue: 0.349, alpha: 0.85)
        context.fillEllipse(in: CGRect(x: 8, y: 8, width: 80, height: 80))
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.setLineWidth(6)
        context.strokeEllipse(in: CGRect(x: 26, y: 26, width: 44, height: 44))
    }

    /// Stands in for the icon of the application the samples were copied from.
    static let applicationIcon = png(width: 256, height: 256) { context in
        let tile = CGRect(x: 26, y: 26, width: 204, height: 204)
        context.addPath(CGPath(roundedRect: tile, cornerWidth: 46, cornerHeight: 46, transform: nil))
        context.clip()
        drawGradient(in: context, width: 256, height: 256)
        context.setStrokeColor(red: 1, green: 1, blue: 1, alpha: 0.9)
        context.setLineWidth(14)
        context.strokeEllipse(in: tile.insetBy(dx: 52, dy: 52))
    }

    /// A wide page image, as a link's metadata would bring.
    static let linkPreview = png(width: 1200, height: 630) { context in
        context.setFillColor(red: 0.07, green: 0.09, blue: 0.16, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 1200, height: 630))
        context.setFillColor(red: 0.2, green: 0.47, blue: 0.96, alpha: 1)
        context.fillEllipse(in: CGRect(x: 760, y: 120, width: 380, height: 380))
        drawLabel("Sample page", in: context, at: CGPoint(x: 80, y: 290), size: 84)
    }

    /// A square site icon.
    static let siteIcon = png(width: 128, height: 128) { context in
        context.setFillColor(red: 0.2, green: 0.47, blue: 0.96, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 128, height: 128))
        context.setFillColor(red: 1, green: 1, blue: 1, alpha: 1)
        context.fillEllipse(in: CGRect(x: 34, y: 34, width: 60, height: 60))
    }

    /// The system's icon for a plain text file, as the thumbnail of the single-file sample.
    static let fileThumbnail: Data = {
        let icon = NSWorkspace.shared.icon(for: .plainText)
        return png(width: 256, height: 256) { context in
            let graphicsContext = NSGraphicsContext(cgContext: context, flipped: false)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = graphicsContext
            icon.draw(in: CGRect(x: 0, y: 0, width: 256, height: 256))
            NSGraphicsContext.restoreGraphicsState()
        }
    }()

    private static func png(width: Int, height: Int, draw: (CGContext) -> Void) -> Data {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                  space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { fatalError("cannot create a \(width)x\(height) drawing context") }
        draw(context)
        guard let image = context.makeImage(),
              let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
        else { fatalError("cannot encode a sample image") }
        return data
    }

    private static func drawGradient(in context: CGContext, width: CGFloat, height: CGFloat) {
        let colors = [
            CGColor(srgbRed: 0.369, green: 0.361, blue: 0.902, alpha: 1),
            CGColor(srgbRed: 1, green: 0.216, blue: 0.373, alpha: 1),
            CGColor(srgbRed: 1, green: 0.584, blue: 0, alpha: 1),
        ]
        guard let gradient = CGGradient(colorsSpace: context.colorSpace, colors: colors as CFArray, locations: [0, 0.6, 1]) else { return }
        context.drawLinearGradient(gradient, start: CGPoint(x: 0, y: height), end: CGPoint(x: width, y: 0), options: [])
    }

    private static func drawLabel(_ text: String, in context: CGContext, at origin: CGPoint, size: CGFloat) {
        let attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): CTFontCreateWithName("Helvetica-Bold" as CFString, size, nil),
            NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 1, alpha: 1),
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        context.textPosition = origin
        CTLineDraw(line, context)
    }
}
