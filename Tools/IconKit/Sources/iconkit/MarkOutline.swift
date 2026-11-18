import CoreGraphics
import Foundation

/// The mark as a vector: the outline of each leaf, traced from the logo's pixels, and the gradient
/// that fills it. This is what the SVG exports are written from, for the places a bitmap does not
/// suit: a glyph that takes the text's colour, or the mark at any size on a page.
///
/// Tracing has three steps. The edge of the mark is followed at half coverage, between pixels, which
/// gives a closed chain of points about a pixel apart for each leaf. The chain is cut at its corners,
/// the tip and the foot of the leaf. Each stretch between two corners is then fitted with as few
/// cubic curves as stay within `tolerance` of the points (Schneider's algorithm), so a leaf comes out
/// as a handful of curves instead of a thousand points, and the pixels' unevenness is gone.
struct MarkOutline {
    struct Leaf {
        /// A closed path in logo pixels, y down.
        var start: CGPoint
        var curves: [(control1: CGPoint, control2: CGPoint, end: CGPoint)]
        /// The leaf's colours from foot to tip.
        var axis: (from: CGPoint, to: CGPoint)
        var stops: [(offset: CGFloat, colour: RGBA)]
    }

    /// The largest leaf first.
    let leaves: [Leaf]
    /// The box the SVG exports use, in logo pixels: the mark's bounding box.
    let bounds: CGRect

    /// How far a fitted curve may stray from the traced edge, in logo pixels.
    static let tolerance: CGFloat = 0.9
    /// A turn sharper than this, measured over `cornerSpan` points either side, is a corner.
    static let cornerAngle: CGFloat = 60 * .pi / 180
    static let cornerSpan = 14
    static let gradientStops = 6

    init(mark: Mark) throws {
        let chains = Self.contours(of: mark).filter { $0.count > 200 }.sorted { $0.count > $1.count }
        guard chains.count == 2 else {
            throw IconKitError("the logo should trace into two leaves, not \(chains.count) shapes")
        }
        var leaves: [Leaf] = []
        for chain in chains {
            let corners = Self.corners(of: chain)
            guard corners.count == 2 else {
                throw IconKitError("a leaf should have a tip and a foot, not \(corners.count) corners")
            }
            var curves: [(CGPoint, CGPoint, CGPoint)] = []
            for (index, corner) in corners.enumerated() {
                let next = corners[(index + 1) % corners.count]
                let count = (next - corner + chain.count) % chain.count
                let stretch = (0...count).map { chain[(corner + $0) % chain.count] }
                curves += CurveFit.fit(stretch, tolerance: Self.tolerance).map { ($0.1, $0.2, $0.3) }
            }
            // The foot is the lower corner: the leaves grow upwards.
            let ends = corners.map { chain[$0] }.sorted { $0.y > $1.y }
            let axis = (from: ends[0], to: ends[1])
            leaves.append(Leaf(start: chain[corners[0]], curves: curves, axis: axis,
                               stops: Self.stops(along: axis, chain: chain, mark: mark)))
        }
        self.leaves = leaves
        bounds = mark.bounds
    }

    // MARK: Paths

    /// The leaves as one path, mapped from logo pixels with `transform`.
    func path(_ transform: CGAffineTransform = .identity) -> CGPath {
        let path = CGMutablePath()
        for index in leaves.indices { path.addPath(leafPath(index, transform)) }
        return path
    }

    func leafPath(_ index: Int, _ transform: CGAffineTransform = .identity) -> CGPath {
        let leaf = leaves[index]
        let path = CGMutablePath()
        path.move(to: leaf.start, transform: transform)
        for curve in leaf.curves {
            path.addCurve(to: curve.end, control1: curve.control1, control2: curve.control2, transform: transform)
        }
        path.closeSubpath()
        return path
    }

    /// The vector mark drawn into a transparent square, as `AppIcon.markAlone` draws the bitmap one.
    func image(pixels: Int, margin: CGFloat = 0.04, solid: RGBA? = nil) -> CGImage {
        let context = Rasterizer.makeContext(width: pixels, height: pixels)
        let side = CGFloat(pixels)
        let scale = side * (1 - 2 * margin) / max(bounds.width, bounds.height)
        // Logo pixels are y-down, the bitmap y-up.
        let transform = CGAffineTransform(translationX: -bounds.midX, y: -bounds.midY)
            .concatenating(CGAffineTransform(scaleX: scale, y: -scale))
            .concatenating(CGAffineTransform(translationX: side / 2, y: side / 2))
        for (index, leaf) in leaves.enumerated() {
            context.saveGState()
            context.addPath(leafPath(index, transform))
            if let solid {
                context.setFillColor(solid.cgColor)
                context.fillPath()
            } else {
                context.clip()
                guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                                colors: leaf.stops.map(\.colour.cgColor) as CFArray,
                                                locations: leaf.stops.map(\.offset))
                else { fatalError("Invalid gradient") }
                context.drawLinearGradient(gradient, start: leaf.axis.from.applying(transform), end: leaf.axis.to.applying(transform),
                                           options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            }
            context.restoreGState()
        }
        guard let image = context.makeImage() else { fatalError("Could not read back the mark") }
        return image
    }

    // MARK: SVG

    /// The height of the SVG's box; its width follows the mark's proportions.
    static let svgHeight: CGFloat = 100

    private var svgTransform: CGAffineTransform {
        let scale = Self.svgHeight / bounds.height
        return CGAffineTransform(translationX: -bounds.minX, y: -bounds.minY).concatenating(CGAffineTransform(scaleX: scale, y: scale))
    }

    private static func number(_ value: CGFloat) -> String {
        var text = String(format: "%.2f", Double(value))
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text == "-0" ? "0" : text
    }

    private static func point(_ point: CGPoint) -> String { "\(number(point.x)) \(number(point.y))" }

    /// The `d` attribute of one leaf in the SVG's box.
    func svgPathData(_ index: Int) -> String {
        let leaf = leaves[index], transform = svgTransform
        var data = "M\(Self.point(leaf.start.applying(transform)))"
        for curve in leaf.curves {
            data += "C" + [curve.control1, curve.control2, curve.end].map { Self.point($0.applying(transform)) }.joined(separator: " ")
        }
        return data + "Z"
    }

    private var svgViewBox: String { "0 0 \(Self.number(bounds.width * Self.svgHeight / bounds.height)) \(Self.number(Self.svgHeight))" }

    /// The mark in its own colours.
    var svg: String {
        let transform = svgTransform
        var gradients = "", paths = ""
        for (index, leaf) in leaves.enumerated() {
            let from = leaf.axis.from.applying(transform), to = leaf.axis.to.applying(transform)
            gradients += "    <linearGradient id=\"leaf\(index + 1)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(Self.number(from.x))\" y1=\"\(Self.number(from.y))\" x2=\"\(Self.number(to.x))\" y2=\"\(Self.number(to.y))\">\n"
            for stop in leaf.stops {
                gradients += "      <stop offset=\"\(Self.number(stop.offset))\" stop-color=\"\(stop.colour.hex)\"/>\n"
            }
            gradients += "    </linearGradient>\n"
            paths += "  <path fill=\"url(#leaf\(index + 1))\" d=\"\(svgPathData(index))\"/>\n"
        }
        return """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(svgViewBox)" role="img" aria-label="Pasto">
              <defs>
            \(gradients)  </defs>
            \(paths)</svg>

            """
    }

    /// The mark in one colour, the text's.
    var monochromeSVG: String {
        """
        <svg xmlns="http://www.w3.org/2000/svg" viewBox="\(svgViewBox)" role="img" aria-label="Pasto" fill="currentColor">
          <path d="\(leaves.indices.map(svgPathData).joined())"/>
        </svg>

        """
    }

    // MARK: Tracing

    /// The closed chains of points where the mark's coverage crosses one half (marching squares,
    /// with the crossing interpolated along each cell edge).
    private static func contours(of mark: Mark) -> [[CGPoint]] {
        let width = mark.width, height = mark.height
        func value(_ x: Int, _ y: Int) -> Float { mark.coverage[y * width + x] }
        let level: Float = 0.5
        // A crossing is named by the cell edge it lies on: the pixel at its start and its direction.
        func across(_ x: Int, _ y: Int) -> Int { (y * width + x) * 2 }
        func down(_ x: Int, _ y: Int) -> Int { (y * width + x) * 2 + 1 }
        var points: [Int: CGPoint] = [:]
        var links: [Int: [Int]] = [:]
        func crossing(_ key: Int) -> CGPoint {
            let pixel = key / 2, x = pixel % width, y = pixel / width
            let a = value(x, y)
            if key % 2 == 0 {
                let b = value(x + 1, y)
                return CGPoint(x: CGFloat(x) + CGFloat((level - a) / (b - a)), y: CGFloat(y))
            }
            let b = value(x, y + 1)
            return CGPoint(x: CGFloat(x), y: CGFloat(y) + CGFloat((level - a) / (b - a)))
        }
        func join(_ a: Int, _ b: Int) {
            points[a] = points[a] ?? crossing(a)
            points[b] = points[b] ?? crossing(b)
            links[a, default: []].append(b)
            links[b, default: []].append(a)
        }
        for y in 0..<(height - 1) {
            for x in 0..<(width - 1) {
                let topLeft = value(x, y) >= level, topRight = value(x + 1, y) >= level
                let bottomRight = value(x + 1, y + 1) >= level, bottomLeft = value(x, y + 1) >= level
                let kind = (topLeft ? 8 : 0) | (topRight ? 4 : 0) | (bottomRight ? 2 : 0) | (bottomLeft ? 1 : 0)
                guard kind != 0, kind != 15 else { continue }
                let top = across(x, y), bottom = across(x, y + 1), left = down(x, y), right = down(x + 1, y)
                switch kind {
                case 1, 14: join(left, bottom)
                case 2, 13: join(bottom, right)
                case 3, 12: join(left, right)
                case 4, 11: join(top, right)
                case 6, 9: join(top, bottom)
                case 7, 8: join(top, left)
                default:
                    // Two opposite corners inside: the cell's middle says which way they connect.
                    let middle = (value(x, y) + value(x + 1, y) + value(x + 1, y + 1) + value(x, y + 1)) / 4
                    if (kind == 5) == (middle >= level) {
                        join(top, left); join(bottom, right)
                    } else {
                        join(top, right); join(left, bottom)
                    }
                }
            }
        }
        var chains: [[CGPoint]] = []
        var visited = Set<Int>()
        for start in links.keys.sorted() where !visited.contains(start) {
            var chain: [CGPoint] = []
            var previous = -1, current = start
            while !visited.contains(current) {
                visited.insert(current)
                chain.append(points[current]!)
                guard let next = links[current]?.first(where: { $0 != previous && !visited.contains($0) }) else { break }
                previous = current
                current = next
            }
            chains.append(chain)
        }
        return chains
    }

    /// The indices of the chain's corners, in order.
    private static func corners(of chain: [CGPoint]) -> [Int] {
        let count = chain.count, span = cornerSpan
        func turn(_ index: Int) -> CGFloat {
            let before = chain[(index - span + count) % count], here = chain[index], after = chain[(index + span) % count]
            let a = CGVector(dx: here.x - before.x, dy: here.y - before.y), b = CGVector(dx: after.x - here.x, dy: after.y - here.y)
            return abs(atan2(a.dx * b.dy - a.dy * b.dx, a.dx * b.dx + a.dy * b.dy))
        }
        let turns = (0..<count).map(turn)
        var corners: [Int] = []
        for index in 0..<count where turns[index] > cornerAngle {
            // The sharpest point of the bend, not every point on it.
            let isPeak = (-span...span).allSatisfy { offset in
                let other = (index + offset + count) % count
                return turns[other] < turns[index] || (turns[other] == turns[index] && other >= index)
            }
            if isPeak { corners.append(index) }
        }
        return corners
    }

    /// The leaf's colour at even steps from foot to tip: the mean of the solid pixels in the band
    /// across the axis at each step.
    private static func stops(along axis: (from: CGPoint, to: CGPoint), chain: [CGPoint], mark: Mark) -> [(offset: CGFloat, colour: RGBA)] {
        let outline = CGMutablePath()
        outline.addLines(between: chain)
        outline.closeSubpath()
        let box = outline.boundingBox.integral
        let direction = CGVector(dx: axis.to.x - axis.from.x, dy: axis.to.y - axis.from.y)
        let length = direction.dx * direction.dx + direction.dy * direction.dy
        var sums = [SIMD3<Double>](repeating: SIMD3(repeating: 0), count: gradientStops)
        var counts = [Double](repeating: 0, count: gradientStops)
        guard let data = mark.image.dataProvider?.data, let bytes = CFDataGetBytePtr(data) else { return [] }
        let stride = mark.image.bytesPerRow
        for y in Int(box.minY)..<Int(box.maxY) {
            for x in Int(box.minX)..<Int(box.maxX) where mark.coverage[y * mark.width + x] == 1 {
                guard outline.contains(CGPoint(x: x, y: y)) else { continue }
                let along = ((CGFloat(x) - axis.from.x) * direction.dx + (CGFloat(y) - axis.from.y) * direction.dy) / length
                let position = min(max(along, 0), 1) * CGFloat(gradientStops - 1)
                // Each pixel is shared between the two steps it lies between.
                let lower = min(Int(position), gradientStops - 2), share = Double(position) - Double(lower)
                let offset = y * stride + x * 4
                let colour = SIMD3(Double(bytes[offset]), Double(bytes[offset + 1]), Double(bytes[offset + 2]))
                sums[lower] += colour * (1 - share); counts[lower] += 1 - share
                sums[lower + 1] += colour * share; counts[lower + 1] += share
            }
        }
        return (0..<gradientStops).map { index in
            let mean = sums[index] / max(counts[index], 1) / 255
            return (CGFloat(index) / CGFloat(gradientStops - 1), RGBA(red: mean.x, green: mean.y, blue: mean.z))
        }
    }
}

extension RGBA {
    /// `#rrggbb`.
    var hex: String {
        String(format: "#%02x%02x%02x", Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }
}

/// Fits a chain of points with cubic Bézier curves (Philip J. Schneider, "An Algorithm for
/// Automatically Fitting Digitized Curves", Graphics Gems, 1990).
enum CurveFit {
    typealias Cubic = (CGPoint, CGPoint, CGPoint, CGPoint)

    /// Curves through `points` from the first to the last, none further than `tolerance` from them.
    static func fit(_ points: [CGPoint], tolerance: CGFloat) -> [Cubic] {
        guard points.count > 1 else { return [] }
        let reach = min(6, points.count - 1)
        let leaving = unit(points[reach] - points[0])
        let arriving = unit(points[points.count - 1 - reach] - points[points.count - 1])
        return fit(points[...], leaving, arriving, tolerance * tolerance)
    }

    private static func fit(_ points: ArraySlice<CGPoint>, _ leaving: CGVector, _ arriving: CGVector, _ limit: CGFloat) -> [Cubic] {
        let first = points[points.startIndex], last = points[points.endIndex - 1]
        if points.count == 2 {
            let reach = distance(first, last) / 3
            return [(first, first + leaving * reach, last + arriving * reach, last)]
        }
        var parameters = chordLengths(points)
        var curve = generate(points, parameters, leaving, arriving)
        var (worst, split) = maxError(points, curve, parameters)
        if worst < limit { return [curve] }
        // Close enough to be worth moving each point's parameter to where the curve is nearest.
        if worst < limit * 16 {
            for _ in 0..<4 {
                parameters = zip(points, parameters).map { newton(curve, $0, $1) }
                curve = generate(points, parameters, leaving, arriving)
                (worst, split) = maxError(points, curve, parameters)
                if worst < limit { return [curve] }
            }
        }
        // Too far: two curves, meeting where the fit was worst, with one tangent between them.
        let reach = min(6, split - points.startIndex, points.endIndex - 1 - split)
        let through = unit(points[split - reach] - points[split + reach])
        return fit(points[points.startIndex...split], leaving, through, limit)
            + fit(points[split...], through * -1, arriving, limit)
    }

    private static func chordLengths(_ points: ArraySlice<CGPoint>) -> [CGFloat] {
        var lengths: [CGFloat] = [0]
        for index in (points.startIndex + 1)..<points.endIndex {
            lengths.append(lengths[lengths.count - 1] + distance(points[index], points[index - 1]))
        }
        let total = lengths[lengths.count - 1]
        return lengths.map { $0 / total }
    }

    /// The least-squares cubic with the given end tangents.
    private static func generate(_ points: ArraySlice<CGPoint>, _ parameters: [CGFloat], _ leaving: CGVector, _ arriving: CGVector) -> Cubic {
        let first = points[points.startIndex], last = points[points.endIndex - 1]
        var c00: CGFloat = 0, c01: CGFloat = 0, c11: CGFloat = 0, x0: CGFloat = 0, x1: CGFloat = 0
        for (point, t) in zip(points, parameters) {
            let b0 = (1 - t) * (1 - t) * (1 - t), b1 = 3 * t * (1 - t) * (1 - t), b2 = 3 * t * t * (1 - t), b3 = t * t * t
            let a0 = leaving * b1, a1 = arriving * b2
            c00 += dot(a0, a0); c01 += dot(a0, a1); c11 += dot(a1, a1)
            let rest = point - (first * (b0 + b1) + last * (b2 + b3))
            x0 += dot(a0, rest); x1 += dot(a1, rest)
        }
        let determinant = c00 * c11 - c01 * c01
        let span = distance(first, last)
        var alpha0 = determinant == 0 ? 0 : (x0 * c11 - x1 * c01) / determinant
        var alpha1 = determinant == 0 ? 0 : (c00 * x1 - c01 * x0) / determinant
        // A handle that came out backwards or vanishing makes a kink: fall back to thirds of the chord.
        if alpha0 < span * 1e-6 || alpha1 < span * 1e-6 {
            alpha0 = span / 3
            alpha1 = span / 3
        }
        return (first, first + leaving * alpha0, last + arriving * alpha1, last)
    }

    private static func maxError(_ points: ArraySlice<CGPoint>, _ curve: Cubic, _ parameters: [CGFloat]) -> (CGFloat, Int) {
        var worst: CGFloat = 0, split = points.startIndex + points.count / 2
        for (offset, t) in parameters.enumerated() {
            let index = points.startIndex + offset
            let gap = point(curve, t) - points[index]
            let error = dot(gap, gap)
            if error >= worst, index > points.startIndex, index < points.endIndex - 1 {
                worst = error
                split = index
            }
        }
        return (worst, split)
    }

    /// One Newton step towards the parameter at which the curve is nearest `target`.
    private static func newton(_ curve: Cubic, _ target: CGPoint, _ t: CGFloat) -> CGFloat {
        let d1 = [(curve.1 - curve.0) * 3, (curve.2 - curve.1) * 3, (curve.3 - curve.2) * 3]
        let d2 = [(d1[1] - d1[0]) * 2, (d1[2] - d1[1]) * 2]
        let gap = point(curve, t) - target
        let first = d1[0] * ((1 - t) * (1 - t)) + d1[1] * (2 * t * (1 - t)) + d1[2] * (t * t)
        let second = d2[0] * (1 - t) + d2[1] * t
        let denominator = dot(first, first) + dot(gap, second)
        guard denominator != 0 else { return t }
        return min(max(t - dot(gap, first) / denominator, 0), 1)
    }

    static func point(_ curve: Cubic, _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        return curve.0 * (u * u * u) + curve.1 * (3 * t * u * u) + curve.2 * (3 * t * t * u) + curve.3 * (t * t * t)
    }

    private static func distance(_ a: CGPoint, _ b: CGPoint) -> CGFloat { hypot(a.x - b.x, a.y - b.y) }
    private static func dot(_ a: CGVector, _ b: CGVector) -> CGFloat { a.dx * b.dx + a.dy * b.dy }
    private static func unit(_ vector: CGVector) -> CGVector {
        let length = hypot(vector.dx, vector.dy)
        return length == 0 ? vector : CGVector(dx: vector.dx / length, dy: vector.dy / length)
    }
}

private func - (a: CGPoint, b: CGPoint) -> CGVector { CGVector(dx: a.x - b.x, dy: a.y - b.y) }
private func + (a: CGPoint, b: CGVector) -> CGPoint { CGPoint(x: a.x + b.dx, y: a.y + b.dy) }
private func + (a: CGPoint, b: CGPoint) -> CGPoint { CGPoint(x: a.x + b.x, y: a.y + b.y) }
private func * (a: CGPoint, b: CGFloat) -> CGPoint { CGPoint(x: a.x * b, y: a.y * b) }
private func * (a: CGVector, b: CGFloat) -> CGVector { CGVector(dx: a.dx * b, dy: a.dy * b) }
private func - (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx - b.dx, dy: a.dy - b.dy) }
private func + (a: CGVector, b: CGVector) -> CGVector { CGVector(dx: a.dx + b.dx, dy: a.dy + b.dy) }
