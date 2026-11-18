import CoreGraphics

/// Where an editing window opens so that several do not hide each other.
nonisolated enum WindowCascade {
    /// The origin of a window that was just centred at `centeredFrame`: moved right and down by
    /// one step per open window (itself included), kept inside the right and bottom edges of
    /// the screen's full frame.
    static func origin(centeredFrame: CGRect, screenFrame: CGRect, windowCount: Int) -> CGPoint {
        let offset = PreviewMetrics.cascadeStep * CGFloat(windowCount)
        var origin = CGPoint(x: centeredFrame.minX + offset, y: centeredFrame.minY - offset)
        if origin.x + centeredFrame.width > screenFrame.maxX {
            origin.x = screenFrame.maxX - centeredFrame.width
        }
        if origin.y < screenFrame.minY {
            origin.y = screenFrame.minY
        }
        return origin
    }
}
