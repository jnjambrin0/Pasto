import Foundation

/// One pixel, 8 bits per channel.
public struct RGBA: Codable, Sendable, Equatable {
    public var r: UInt8
    public var g: UInt8
    public var b: UInt8
    public var a: UInt8

    public init(r: UInt8, g: UInt8, b: UInt8, a: UInt8 = 255) {
        self.r = r
        self.g = g
        self.b = b
        self.a = a
    }

    /// `#RRGGBB`, alpha left out.
    public var hex: String {
        String(format: "#%02X%02X%02X", r, g, b)
    }

    /// Undoes alpha premultiplication so that a translucent pixel reports its real colour.
    public var unpremultiplied: RGBA {
        guard a != 0, a != 255 else { return self }
        func restore(_ channel: UInt8) -> UInt8 {
            UInt8(min(255, (Int(channel) * 255 + Int(a) / 2) / Int(a)))
        }
        return RGBA(r: restore(r), g: restore(g), b: restore(b), a: a)
    }
}

/// An sRGB image held as row-major RGBA bytes with premultiplied alpha, top row first.
public struct Bitmap: Sendable, Equatable {
    public let width: Int
    public let height: Int
    public private(set) var pixels: [UInt8]

    public init(width: Int, height: Int, pixels: [UInt8]) throws {
        guard width > 0, height > 0, pixels.count == width * height * 4 else {
            throw ProbeError.runtime("pixel buffer of \(pixels.count) bytes does not describe a \(width)x\(height) image")
        }
        self.width = width
        self.height = height
        self.pixels = pixels
    }

    public init(width: Int, height: Int, fill: RGBA) {
        precondition(width > 0 && height > 0, "a bitmap needs a positive size")
        self.width = width
        self.height = height
        self.pixels = (0..<width * height).flatMap { _ in [fill.r, fill.g, fill.b, fill.a] }
    }

    public subscript(x: Int, y: Int) -> RGBA {
        get {
            let offset = (y * width + x) * 4
            return RGBA(r: pixels[offset], g: pixels[offset + 1], b: pixels[offset + 2], a: pixels[offset + 3])
        }
        set {
            let offset = (y * width + x) * 4
            pixels[offset] = newValue.r
            pixels[offset + 1] = newValue.g
            pixels[offset + 2] = newValue.b
            pixels[offset + 3] = newValue.a
        }
    }

    /// Mean colour of the `size`×`size` block centred on (`x`, `y`), clipped to the image, with the
    /// number of pixels averaged. The colour is still premultiplied; nil when the centre lies
    /// outside the image.
    public func average(centerX x: Int, centerY y: Int, size: Int) -> (color: RGBA, samples: Int)? {
        guard size > 0, x >= 0, y >= 0, x < width, y < height else { return nil }
        let columns = max(0, x - size / 2)..<min(width, x - size / 2 + size)
        let rows = max(0, y - size / 2)..<min(height, y - size / 2 + size)
        var sums = [0, 0, 0, 0]
        for row in rows {
            for column in columns {
                let offset = (row * width + column) * 4
                for channel in 0..<4 { sums[channel] += Int(pixels[offset + channel]) }
            }
        }
        let count = rows.count * columns.count
        func mean(_ sum: Int) -> UInt8 { UInt8((sum + count / 2) / count) }
        return (RGBA(r: mean(sums[0]), g: mean(sums[1]), b: mean(sums[2]), a: mean(sums[3])), count)
    }
}
