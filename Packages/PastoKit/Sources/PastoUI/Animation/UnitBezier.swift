import Foundation

/// A cubic Bézier timing curve through (0,0) and (1,1), evaluated the way Core Animation and
/// WebKit do: solve x(t) = progress for t, then return y(t).
public nonisolated struct UnitBezier: Sendable, Equatable {
    public let p1x: Double
    public let p1y: Double
    public let p2x: Double
    public let p2y: Double

    public init(_ p1x: Double, _ p1y: Double, _ p2x: Double, _ p2y: Double) {
        self.p1x = p1x
        self.p1y = p1y
        self.p2x = p2x
        self.p2y = p2y
    }

    public static let linear = UnitBezier(0, 0, 1, 1)
    public static let easeIn = UnitBezier(0.42, 0, 1, 1)
    public static let easeOut = UnitBezier(0, 0, 0.58, 1)
    public static let easeInEaseOut = UnitBezier(0.42, 0, 0.58, 1)

    /// The eased value for a linear progress in 0...1.
    public func value(at progress: Double) -> Double {
        if progress <= 0 { return 0 }
        if progress >= 1 { return 1 }
        return sampleY(solveT(forX: progress))
    }

    // Polynomial coefficients of the curve: x(t) = ((ax·t + bx)·t + cx)·t, same for y.
    private var cx: Double { 3 * p1x }
    private var bx: Double { 3 * (p2x - p1x) - cx }
    private var ax: Double { 1 - cx - bx }
    private var cy: Double { 3 * p1y }
    private var by: Double { 3 * (p2y - p1y) - cy }
    private var ay: Double { 1 - cy - by }

    private func sampleX(_ t: Double) -> Double { ((ax * t + bx) * t + cx) * t }
    private func sampleY(_ t: Double) -> Double { ((ay * t + by) * t + cy) * t }
    private func sampleDerivativeX(_ t: Double) -> Double { (3 * ax * t + 2 * bx) * t + cx }

    private func solveT(forX x: Double) -> Double {
        let epsilon = 1e-7

        // Newton–Raphson converges in a few steps for well-behaved curves.
        var t = x
        for _ in 0..<8 {
            let error = sampleX(t) - x
            if abs(error) < epsilon { return t }
            let derivative = sampleDerivativeX(t)
            if abs(derivative) < 1e-6 { break }
            t -= error / derivative
        }

        // Fall back to bisection, which always converges on a monotonic x(t).
        var lower = 0.0
        var upper = 1.0
        t = x
        while lower < upper {
            let sample = sampleX(t)
            if abs(sample - x) < epsilon { return t }
            if x > sample { lower = t } else { upper = t }
            let next = (upper + lower) / 2
            if next == t { break }
            t = next
        }
        return t
    }
}
