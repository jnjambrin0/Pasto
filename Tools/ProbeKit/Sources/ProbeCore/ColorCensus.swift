import Foundation

/// The colours of a rectangle of a bitmap: the most frequent ones plus the brightest and the darkest,
/// which is how the nominal colour of antialiased text or of a flat fill is read from a screenshot.
public enum ColorCensus {
    public struct Entry: Codable, Sendable, Equatable {
        /// Colour with alpha undone.
        public var hex: String
        public var alpha: UInt8
        public var count: Int
    }

    public struct Result: Codable, Sendable, Equatable {
        public var pixels: Int
        public var distinct: Int
        public var top: [Entry]
        public var brightest: Entry
        public var darkest: Entry
    }

    /// Counts the colours inside `x, y, width, height` (pixels, clipped to the image).
    public static func census(of bitmap: Bitmap, x: Int, y: Int, width: Int, height: Int, top: Int = 5) throws -> Result {
        let (left, right) = (max(0, x), min(bitmap.width, x + width))
        let (firstRow, endRow) = (max(0, y), min(bitmap.height, y + height))
        guard left < right, firstRow < endRow else {
            throw ProbeError.targetNotFound("the rectangle lies outside the \(bitmap.width)x\(bitmap.height) image")
        }
        let columns = left..<right
        let rows = firstRow..<endRow
        var counts: [UInt32: Int] = [:]
        for row in rows {
            for column in columns {
                let pixel = bitmap[column, row]
                let key = UInt32(pixel.r) << 24 | UInt32(pixel.g) << 16 | UInt32(pixel.b) << 8 | UInt32(pixel.a)
                counts[key, default: 0] += 1
            }
        }
        func entry(_ key: UInt32, _ count: Int) -> Entry {
            let pixel = RGBA(r: UInt8(key >> 24), g: UInt8(key >> 16 & 0xFF), b: UInt8(key >> 8 & 0xFF), a: UInt8(key & 0xFF))
            return Entry(hex: pixel.unpremultiplied.hex, alpha: pixel.a, count: count)
        }
        func luminance(_ key: UInt32) -> Int {
            Int(key >> 24) * 299 + Int(key >> 16 & 0xFF) * 587 + Int(key >> 8 & 0xFF) * 114
        }
        // Ties are broken by the colour value so that the result does not depend on dictionary order.
        let ordered = counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }
        let byLight = counts.keys.sorted { luminance($0) != luminance($1) ? luminance($0) < luminance($1) : $0 < $1 }
        guard let darkest = byLight.first, let brightest = byLight.last else {
            throw ProbeError.runtime("the rectangle holds no pixels")
        }
        return Result(
            pixels: rows.count * columns.count,
            distinct: counts.count,
            top: ordered.prefix(max(1, top)).map { entry($0.key, $0.value) },
            brightest: entry(brightest, counts[brightest] ?? 0),
            darkest: entry(darkest, counts[darkest] ?? 0)
        )
    }
}
