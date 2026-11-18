import CoreGraphics
import Foundation

// A deliberately small vector model for what IconKit draws itself (the menu bar glyph and the DMG
// background): a `Scene` is an ordered list of layers, each a list of filled (or stroked) paths,
// painted by `Rasterizer`.
//
// Coordinates are design units with the origin at the top-left corner and y growing downwards,
// like a design tool. Transforms are baked into the paths when the scene is built.

/// An sRGB colour.
struct RGBA: Hashable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    init(_ hex: UInt32, alpha: Double = 1) {
        red = Double((hex >> 16) & 0xFF) / 255
        green = Double((hex >> 8) & 0xFF) / 255
        blue = Double(hex & 0xFF) / 255
        self.alpha = alpha
    }

    init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    static let white = RGBA(0xFFFFFF)
    static let black = RGBA(0x000000)

    func opacity(_ alpha: Double) -> RGBA {
        RGBA(red: red, green: green, blue: blue, alpha: alpha)
    }

    var cgColor: CGColor {
        CGColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }

}

struct GradientStop: Sendable {
    var offset: CGFloat
    var color: RGBA

    init(_ offset: CGFloat, _ color: RGBA) {
        self.offset = offset
        self.color = color
    }
}

enum Paint: @unchecked Sendable {
    case solid(RGBA)
    /// Colours are padded beyond both ends.
    case linear(from: CGPoint, to: CGPoint, stops: [GradientStop])
    case radial(center: CGPoint, radius: CGFloat, stops: [GradientStop])

    static func vertical(_ top: RGBA, _ bottom: RGBA, from y0: CGFloat, to y1: CGFloat) -> Paint {
        .linear(from: CGPoint(x: 0, y: y0), to: CGPoint(x: 0, y: y1), stops: [GradientStop(0, top), GradientStop(1, bottom)])
    }
}

/// A drop shadow cast by a whole layer. Offsets and blur are design units; `blur` follows the
/// CoreGraphics (and CSS) convention, which is twice the Gaussian standard deviation.
struct Shadow: Sendable {
    var dy: CGFloat
    var blur: CGFloat
    var color: RGBA
}

enum FillRule: Sendable {
    case nonZero
    case evenOdd
}

struct Item: @unchecked Sendable {
    var path: CGPath
    var paint: Paint
    var fillRule: FillRule = .nonZero
    /// When set, the path is stroked with this width (centred on the path) instead of filled.
    var strokeWidth: CGFloat?
    /// Clips this item only.
    var clip: CGPath?
}

struct Layer: @unchecked Sendable {
    var name: String
    var items: [Item]
    var shadow: Shadow?
    /// Clips the layer and its shadow.
    var clip: CGPath?
}

struct Scene: Sendable {
    var width: CGFloat
    var height: CGFloat
    var layers: [Layer]

    init(width: CGFloat, height: CGFloat, layers: [Layer]) {
        self.width = width
        self.height = height
        self.layers = layers
    }

    init(side: CGFloat, layers: [Layer]) {
        self.init(width: side, height: side, layers: layers)
    }
}

extension CGPath {
    func transformed(_ transform: CGAffineTransform) -> CGPath {
        var copy = transform
        return self.copy(using: &copy) ?? self
    }
}

