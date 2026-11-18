import Foundation

/// Runs of near-constant colour along one row or column of a bitmap: the cheap way to read edges,
/// paddings, corner profiles and border widths out of a screenshot.
public enum Scanline {
    public enum Axis: Sendable, Equatable {
        case row(Int)
        case column(Int)
    }

    /// A stretch of pixels, `start...end` inclusive, measured along the scanned line.
    public struct Run: Codable, Sendable, Equatable {
        public var start: Int
        public var end: Int
        public var length: Int
        /// Colour of the first pixel with alpha undone; nil when the stretch merges several short runs.
        public var hex: String?
        /// Alpha of the first pixel; nil when the stretch merges several short runs.
        public var alpha: UInt8?
        /// How many runs were merged into this stretch (1 for a plain run).
        public var pieces: Int

        public init(start: Int, end: Int, hex: String?, alpha: UInt8?, pieces: Int = 1) {
            self.start = start
            self.end = end
            self.length = end - start + 1
            self.hex = hex
            self.alpha = alpha
            self.pieces = pieces
        }
    }

    /// Where a line differs from the same line of a reference image.
    public struct Difference: Codable, Sendable, Equatable {
        public var first: Int
        public var last: Int
        public var count: Int
    }

    /// The pixels of one row or column, optionally limited to `range` (clamped to the image).
    public static func pixels(of bitmap: Bitmap, along axis: Axis, range: Range<Int>? = nil) throws -> (offset: Int, pixels: [RGBA]) {
        let (fixed, limit, extent) = switch axis {
        case .row(let y): (y, bitmap.height, bitmap.width)
        case .column(let x): (x, bitmap.width, bitmap.height)
        }
        guard (0..<limit).contains(fixed) else {
            throw ProbeError.targetNotFound("line \(fixed) is outside the \(bitmap.width)x\(bitmap.height) image")
        }
        let lower = max(0, range?.lowerBound ?? 0)
        let upper = min(extent, range?.upperBound ?? extent)
        guard lower < upper else { throw ProbeError.usage("the requested range is empty or outside the image") }
        let pixels = (lower..<upper).map { index in
            switch axis {
            case .row(let y): bitmap[index, y]
            case .column(let x): bitmap[x, index]
            }
        }
        return (lower, pixels)
    }

    /// Splits the line into runs whose pixels stay within `tolerance` (largest channel delta, alpha
    /// included) of the run's first pixel. Consecutive runs shorter than `minRun` are merged into
    /// one stretch without a colour, which keeps text and gradients from flooding the output.
    public static func runs(_ pixels: [RGBA], offset: Int = 0, tolerance: Int = 0, minRun: Int = 1) -> [Run] {
        var plain: [Run] = []
        var index = 0
        while index < pixels.count {
            let anchor = pixels[index]
            var end = index
            while end + 1 < pixels.count, delta(pixels[end + 1], anchor) <= tolerance { end += 1 }
            plain.append(Run(start: offset + index, end: offset + end, hex: anchor.unpremultiplied.hex, alpha: anchor.a))
            index = end + 1
        }
        guard minRun > 1 else { return plain }

        var merged: [Run] = []
        for run in plain {
            if run.length < minRun, let last = merged.last, last.hex == nil {
                merged[merged.count - 1] = Run(start: last.start, end: run.end, hex: nil, alpha: nil, pieces: last.pieces + 1)
            } else if run.length < minRun {
                merged.append(Run(start: run.start, end: run.end, hex: nil, alpha: nil))
            } else {
                merged.append(run)
            }
        }
        return merged
    }

    /// First and last position where two lines differ by more than `tolerance`, and how many do.
    public static func difference(_ a: [RGBA], _ b: [RGBA], offset: Int = 0, tolerance: Int = 0) -> Difference? {
        var first: Int?
        var last = 0
        var count = 0
        for index in 0..<min(a.count, b.count) where delta(a[index], b[index]) > tolerance {
            if first == nil { first = offset + index }
            last = offset + index
            count += 1
        }
        return first.map { Difference(first: $0, last: last, count: count) }
    }

    private static func delta(_ a: RGBA, _ b: RGBA) -> Int {
        max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)), abs(Int(a.a) - Int(b.a)))
    }
}
