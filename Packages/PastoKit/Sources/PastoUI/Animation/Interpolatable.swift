import CoreGraphics

/// A value that can be blended linearly between two states.
public protocol Interpolatable {
    static func interpolate(from start: Self, to end: Self, progress: Double) -> Self
}

extension CGFloat: Interpolatable {
    public nonisolated static func interpolate(from start: CGFloat, to end: CGFloat, progress: Double) -> CGFloat {
        start + (end - start) * progress
    }
}

extension CGPoint: Interpolatable {
    public nonisolated static func interpolate(from start: CGPoint, to end: CGPoint, progress: Double) -> CGPoint {
        CGPoint(
            x: .interpolate(from: start.x, to: end.x, progress: progress),
            y: .interpolate(from: start.y, to: end.y, progress: progress)
        )
    }
}

extension CGSize: Interpolatable {
    public nonisolated static func interpolate(from start: CGSize, to end: CGSize, progress: Double) -> CGSize {
        CGSize(
            width: .interpolate(from: start.width, to: end.width, progress: progress),
            height: .interpolate(from: start.height, to: end.height, progress: progress)
        )
    }
}

extension CGRect: Interpolatable {
    public nonisolated static func interpolate(from start: CGRect, to end: CGRect, progress: Double) -> CGRect {
        CGRect(
            origin: .interpolate(from: start.origin, to: end.origin, progress: progress),
            size: .interpolate(from: start.size, to: end.size, progress: progress)
        )
    }
}
