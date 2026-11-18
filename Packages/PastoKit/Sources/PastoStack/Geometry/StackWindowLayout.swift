import CoreGraphics
import Foundation

/// The geometry of the stack's window.
///
/// The window is transparent and never changes size as rows come and go: it is as wide as the
/// panel plus its margins and as tall as the panel may ever get, and the visible panel grows
/// downwards inside it from the top. Screen coordinates, y growing upwards.
nonisolated enum StackWindowLayout {
    /// The window's size for a panel that may grow to `heightLimit`.
    static func windowSize(heightLimit: CGFloat) -> CGSize {
        CGSize(
            width: StackMetrics.Panel.width + 2 * StackMetrics.Panel.margin,
            height: heightLimit + 2 * StackMetrics.Panel.margin
        )
    }

    /// The window's frame for a height limit, keeping its top-left corner where it is.
    static func windowFrame(current: CGRect, heightLimit: CGFloat) -> CGRect {
        let size = windowSize(heightLimit: heightLimit)
        return CGRect(x: current.minX, y: current.maxY - size.height, width: size.width, height: size.height)
    }

    /// The panel's maximum height: what the user chose by resizing or, until then, a share of
    /// the screen the panel is on.
    static func heightLimit(stored: Double, visibleScreenHeight: CGFloat) -> CGFloat {
        stored > 0 ? stored : (StackMetrics.Window.defaultHeightFraction * visibleScreenHeight).rounded(.down)
    }

    /// The height limit a resize asks for, which has a floor but no ceiling.
    static func resizedHeightLimit(_ requested: CGFloat) -> CGFloat {
        max(requested, StackMetrics.Window.minimumHeightLimit)
    }

    /// The screen the window belongs to: the one nearest to a point just inside its top edge.
    /// `nil` when there are no screens.
    static func screenIndex(forWindowFrame frame: CGRect, screenFrames: [CGRect]) -> Int? {
        let anchor = CGPoint(x: frame.midX, y: frame.maxY - StackMetrics.Window.screenAnchorInset)
        return screenFrames.indices.min { distance(from: anchor, to: screenFrames[$0]) < distance(from: anchor, to: screenFrames[$1]) }
    }

    private static func distance(from point: CGPoint, to rect: CGRect) -> CGFloat {
        let dx = max(rect.minX - point.x, 0, point.x - rect.maxX)
        let dy = max(rect.minY - point.y, 0, point.y - rect.maxY)
        return hypot(dx, dy)
    }

    /// Splits a position into the whole points a window can be placed at and the rest, which the
    /// content makes up for by shifting inside the window. The position is first rounded to a
    /// device pixel, so that the panel moves in pixel steps even though windows move in points.
    static func pixelAligned(_ origin: CGPoint, scale: CGFloat) -> (windowOrigin: CGPoint, contentShift: CGPoint) {
        func aligned(_ value: CGFloat) -> (whole: CGFloat, rest: CGFloat) {
            let rounded = (value * scale + 0.5).rounded(.down) / scale
            let whole = rounded.rounded(.down)
            return (whole, rounded - whole)
        }
        let x = aligned(origin.x)
        let y = aligned(origin.y)
        return (CGPoint(x: x.whole, y: y.whole), CGPoint(x: x.rest, y: y.rest))
    }

    /// A rectangle from the window server (origin at the top-left corner of the main screen, y
    /// growing downwards) in screen coordinates.
    static func screenRect(fromWindowServer rect: CGRect, mainScreenMaxY: CGFloat) -> CGRect {
        CGRect(x: rect.minX, y: mainScreenMaxY - rect.maxY, width: rect.width, height: rect.height)
    }
}
