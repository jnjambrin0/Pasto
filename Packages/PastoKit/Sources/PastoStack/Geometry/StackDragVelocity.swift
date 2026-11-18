import CoreGraphics
import Foundation

/// The pointer's speed during a drag, in points per second on each axis, lightly smoothed.
nonisolated struct StackDragVelocity {
    /// Not a number until the second sample: one sample says nothing about speed.
    private(set) var value = CGPoint(x: CGFloat.nan, y: CGFloat.nan)
    private var lastPointer: CGPoint
    private var lastTime: TimeInterval

    init(pointer: CGPoint, time: TimeInterval) {
        lastPointer = pointer
        lastTime = time
    }

    mutating func update(pointer: CGPoint, time: TimeInterval) {
        let elapsed = time - lastTime
        // Samples this close together would turn rounding noise into huge speeds.
        guard elapsed >= StackMetrics.Snap.minimumSampleInterval else { return }
        for axis in SnapAxis.allCases {
            let raw = (pointer[axis] - lastPointer[axis]) / elapsed
            value[axis] = Self.smoothed(raw, previous: value[axis], elapsed: elapsed)
        }
        lastPointer = pointer
        lastTime = time
    }

    /// The angle between the direction of movement and `axis`, from 0 (straight along it) to
    /// π/2 (straight across). `nil` while the speed is unknown.
    func angle(from axis: SnapAxis) -> CGFloat? {
        guard !value.x.isNaN, !value.y.isNaN else { return nil }
        return atan2(abs(value[axis.other]), abs(value[axis]))
    }

    /// After a pause or a change of direction the old speed no longer describes the movement,
    /// so the new sample stands alone.
    private static func smoothed(_ raw: CGFloat, previous: CGFloat, elapsed: TimeInterval) -> CGFloat {
        if previous.isNaN || elapsed > StackMetrics.Snap.staleSampleInterval || raw * previous < 0 {
            return raw
        }
        return StackMetrics.Snap.newSampleWeight * raw + (1 - StackMetrics.Snap.newSampleWeight) * previous
    }
}
