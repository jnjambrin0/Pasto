import CoreGraphics
import Foundation

/// A rectangle in points with a top-left origin, encoded as `{x, y, w, h}`.
public struct Frame: Codable, Sendable, Equatable {
    public var x: Double
    public var y: Double
    public var w: Double
    public var h: Double

    public init(x: Double, y: Double, w: Double, h: Double) {
        self.x = x
        self.y = y
        self.w = w
        self.h = h
    }

    public init(_ rect: CGRect) {
        self.init(x: rect.origin.x, y: rect.origin.y, w: rect.width, h: rect.height)
    }

    /// Parses `x,y,w,h`.
    public init(parsing text: String) throws {
        let numbers = try Geometry.numbers(in: text, count: 4, shape: "x,y,w,h")
        guard numbers[2] > 0, numbers[3] > 0 else {
            throw ProbeError.usage("rectangle '\(text)' must have a positive width and height")
        }
        self.init(x: numbers[0], y: numbers[1], w: numbers[2], h: numbers[3])
    }

    public var cgRect: CGRect { CGRect(x: x, y: y, width: w, height: h) }
    public var area: Double { w * h }
}

public enum Geometry {
    /// Parses `x,y` into a point.
    public static func point(parsing text: String) throws -> CGPoint {
        let numbers = try numbers(in: text, count: 2, shape: "x,y")
        return CGPoint(x: numbers[0], y: numbers[1])
    }

    static func numbers(in text: String, count: Int, shape: String) throws -> [Double] {
        let parts = text.split(separator: ",", omittingEmptySubsequences: false)
        let numbers = parts.compactMap { Double($0.trimmingCharacters(in: .whitespaces)) }
        guard parts.count == count, numbers.count == count, numbers.allSatisfy(\.isFinite) else {
            throw ProbeError.usage("expected \(shape) but got '\(text)'")
        }
        return numbers
    }
}
