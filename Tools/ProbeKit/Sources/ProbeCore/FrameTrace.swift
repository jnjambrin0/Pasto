import Foundation

/// Per-frame measurements over a `frames` recording: the colour of fixed points, where an edge
/// sits along a line, and how far a region has gone from its first look to its last. Turns a
/// directory of PNGs into the time series an animation is fitted against.
public enum FrameTrace {
    /// A line to search for the first (or last) pixel that differs from a background colour.
    public struct Edge: Sendable, Equatable {
        public var axis: Scanline.Axis
        public var range: Range<Int>
        public var background: RGBA
        public var tolerance: Int
        public var fromEnd: Bool

        public init(axis: Scanline.Axis, range: Range<Int>, background: RGBA, tolerance: Int, fromEnd: Bool) {
            self.axis = axis
            self.range = range
            self.background = background
            self.tolerance = tolerance
            self.fromEnd = fromEnd
        }
    }

    /// One frame listed in a recording's `index.csv`.
    public struct IndexEntry: Sendable, Equatable {
        public var file: String
        public var milliseconds: Double
    }

    /// Reads `index.csv` (`frame,t_ms`) of a `frames` recording, in time order.
    public static func index(of directory: URL) throws -> [IndexEntry] {
        let url = directory.appendingPathComponent("index.csv")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else {
            throw ProbeError.targetNotFound("no index.csv in \(directory.path); record with 'pastoprobe frames' first")
        }
        return text.split(whereSeparator: \.isNewline).dropFirst().compactMap { line in
            let parts = line.split(separator: ",")
            guard parts.count == 2, let milliseconds = Double(parts[1]) else { return nil }
            return IndexEntry(file: String(parts[0]), milliseconds: milliseconds)
        }.sorted { $0.milliseconds < $1.milliseconds }
    }

    /// Largest per-channel difference between two colours (alpha ignored).
    public static func distance(_ a: RGBA, _ b: RGBA) -> Int {
        max(abs(Int(a.r) - Int(b.r)), abs(Int(a.g) - Int(b.g)), abs(Int(a.b) - Int(b.b)))
    }

    /// Image coordinate of the first pixel along the edge's line (scanning from the end when
    /// `fromEnd`) whose colour differs from the background by more than the tolerance; nil when
    /// the whole line matches the background.
    public static func edge(_ edge: Edge, in bitmap: Bitmap) throws -> Int? {
        let (offset, pixels) = try Scanline.pixels(of: bitmap, along: edge.axis, range: edge.range)
        let indices = edge.fromEnd ? Array(pixels.indices.reversed()) : Array(pixels.indices)
        for index in indices where distance(pixels[index], edge.background) > edge.tolerance {
            return offset + index
        }
        return nil
    }

    /// How far `frame` has travelled from `start` towards `end` inside `rect` (image pixels):
    /// the least-squares coefficient `k` in `frame ≈ start + k · (end − start)`, over the RGB
    /// channels of every pixel. For a cross-fade it is the opacity of the incoming state; for a
    /// motion it rises from 0 to 1 without being proportional to distance. Nil when `start` and
    /// `end` are identical inside the rectangle.
    public static func progress(_ frame: Bitmap, start: Bitmap, end: Bitmap, rect: (x: Int, y: Int, w: Int, h: Int)) -> Double? {
        let x0 = max(0, rect.x), y0 = max(0, rect.y)
        let x1 = min(frame.width, start.width, end.width, rect.x + rect.w)
        let y1 = min(frame.height, start.height, end.height, rect.y + rect.h)
        guard x0 < x1, y0 < y1 else { return nil }
        var numerator = 0.0
        var denominator = 0.0
        for y in y0..<y1 {
            for x in x0..<x1 {
                let f = frame[x, y], s = start[x, y], e = end[x, y]
                for (fc, sc, ec) in [(f.r, s.r, e.r), (f.g, s.g, e.g), (f.b, s.b, e.b)] {
                    let delta = Double(ec) - Double(sc)
                    numerator += (Double(fc) - Double(sc)) * delta
                    denominator += delta * delta
                }
            }
        }
        return denominator > 0 ? numerator / denominator : nil
    }
}
