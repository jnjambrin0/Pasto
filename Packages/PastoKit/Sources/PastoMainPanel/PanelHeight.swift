import Foundation

/// The rules for the panel's user-adjustable height.
nonisolated enum PanelHeight {
    /// Height shown while the user drags the resize handle. Inside the allowed range it follows
    /// the pointer; outside, it gives way by the square root of the overshoot, like a rubber band.
    static func rubberBanded(_ proposed: CGFloat) -> CGFloat {
        let minimum = MainPanelMetrics.minimumHeight
        let maximum = MainPanelMetrics.maximumHeight
        if proposed < minimum {
            return minimum - (minimum - proposed).squareRoot().rounded()
        }
        if proposed > maximum {
            return maximum + (proposed - maximum).squareRoot().rounded()
        }
        return proposed
    }

    /// Height the panel settles at when the drag ends.
    static func clamped(_ height: CGFloat) -> CGFloat {
        min(max(height, MainPanelMetrics.minimumHeight), MainPanelMetrics.maximumHeight)
    }
}
