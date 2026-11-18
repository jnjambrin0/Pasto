import CoreGraphics
import Foundation

/// Draws a `Scene` into an sRGB bitmap with CoreGraphics.
enum Rasterizer {
    /// Renders `scene` scaled uniformly to `pixelWidth` × `pixelHeight`, with `background` (if any)
    /// filled first.
    /// `crop` selects the part of the scene that fills the bitmap (the whole scene by default).
    /// `underlay`, when given, is drawn first and fills the whole bitmap (cropped to its aspect ratio
    /// around the centre); the scene is painted over it.
    static func render(_ scene: Scene, pixelWidth: Int, pixelHeight: Int, crop: CGRect? = nil, background: RGBA? = nil,
                       underlay: CGImage? = nil) -> CGImage {
        let context = makeContext(width: pixelWidth, height: pixelHeight)
        if let background {
            context.setFillColor(background.cgColor)
            context.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        }
        if let underlay {
            let target = CGFloat(pixelWidth) / CGFloat(pixelHeight)
            let source = CGFloat(underlay.width) / CGFloat(underlay.height)
            // Aspect fill: the part of the underlay that keeps the bitmap's proportions, centred.
            let cropRect = source > target
                ? CGRect(x: (CGFloat(underlay.width) - CGFloat(underlay.height) * target) / 2, y: 0,
                         width: CGFloat(underlay.height) * target, height: CGFloat(underlay.height))
                : CGRect(x: 0, y: (CGFloat(underlay.height) - CGFloat(underlay.width) / target) / 2,
                         width: CGFloat(underlay.width), height: CGFloat(underlay.width) / target)
            if let cropped = underlay.cropping(to: cropRect.integral) {
                context.draw(cropped, in: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
            }
        }
        let box = crop ?? CGRect(x: 0, y: 0, width: scene.width, height: scene.height)
        let scale = CGFloat(pixelWidth) / box.width
        context.translateBy(x: 0, y: CGFloat(pixelHeight))
        context.scaleBy(x: scale, y: -scale)
        context.translateBy(x: -box.minX, y: -box.minY)
        for layer in scene.layers {
            draw(layer, in: context, scale: scale)
        }
        guard let image = context.makeImage() else { fatalError("Could not read back a \(pixelWidth)×\(pixelHeight) bitmap") }
        return image
    }

    static func render(_ scene: Scene, pixels: Int) -> CGImage {
        render(scene, pixelWidth: pixels, pixelHeight: Int((CGFloat(pixels) * scene.height / scene.width).rounded()))
    }

    /// An sRGB bitmap context; `opaque` drops the alpha channel, so a PNG made from it has none.
    static func makeContext(width: Int, height: Int, opaque: Bool = false) -> CGContext {
        let alpha = opaque ? CGImageAlphaInfo.noneSkipLast : CGImageAlphaInfo.premultipliedLast
        guard
            let space = CGColorSpace(name: CGColorSpace.sRGB),
            let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: space, bitmapInfo: alpha.rawValue)
        else { fatalError("Could not create a \(width)×\(height) bitmap context") }
        context.interpolationQuality = .high
        context.setShouldAntialias(true)
        return context
    }

    private static func draw(_ layer: Layer, in context: CGContext, scale: CGFloat) {
        context.saveGState()
        defer { context.restoreGState() }
        if let clip = layer.clip {
            context.addPath(clip)
            context.clip()
        }
        if let shadow = layer.shadow {
            // CoreGraphics measures shadows in device pixels, ignoring the transform; the bitmap is
            // y-up, so "down" is a negative offset.
            context.setShadow(offset: CGSize(width: 0, height: -shadow.dy * scale),
                              blur: shadow.blur * scale, color: shadow.color.cgColor)
        }
        // A transparency layer makes the shadow apply to the layer as a whole.
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        for item in layer.items {
            draw(item, in: context)
        }
        context.endTransparencyLayer()
    }

    private static func draw(_ item: Item, in context: CGContext) {
        context.saveGState()
        defer { context.restoreGState() }
        if let clip = item.clip {
            context.addPath(clip)
            context.clip()
        }
        let shape = item.strokeWidth.map {
            item.path.copy(strokingWithWidth: $0, lineCap: .round, lineJoin: .round, miterLimit: 10)
        } ?? item.path
        let rule: CGPathFillRule = item.strokeWidth == nil && item.fillRule == .evenOdd ? .evenOdd : .winding

        switch item.paint {
        case let .solid(color):
            context.addPath(shape)
            context.setFillColor(color.cgColor)
            context.fillPath(using: rule)
        case let .linear(from, to, stops):
            context.addPath(shape)
            context.clip(using: rule)
            context.drawLinearGradient(gradient(stops), start: from, end: to,
                                       options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        case let .radial(center, radius, stops):
            context.addPath(shape)
            context.clip(using: rule)
            context.drawRadialGradient(gradient(stops), startCenter: center, startRadius: 0, endCenter: center,
                                       endRadius: radius, options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
        }
    }

    private static func gradient(_ stops: [GradientStop]) -> CGGradient {
        guard let gradient = CGGradient(
            colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
            colors: stops.map(\.color.cgColor) as CFArray,
            locations: stops.map(\.offset))
        else { fatalError("Invalid gradient") }
        return gradient
    }
}
