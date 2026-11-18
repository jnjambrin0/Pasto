import CoreGraphics
import Foundation

/// What a press on the stack's window is for.
nonisolated enum StackPointerTarget: Equatable {
    /// The bottom edge of the panel: drags change its maximum height.
    case resize
    /// Empty panel surface: drags move the window.
    case move
    /// Not the panel's business: the transparent margin, a row or a control.
    case passThrough
}

/// Decides what lies under the pointer.
///
/// All rectangles and points share one coordinate space whose y grows downwards: the one of the
/// view that fills the window.
nonisolated struct StackHitTest {
    /// The visible, rounded panel.
    var panelFrame: CGRect
    /// The scrolling list, which starts under the header.
    var listFrame: CGRect
    var cardFrames: [StackRow.ID: CGRect]

    func isInsidePanel(_ point: CGPoint) -> Bool {
        guard panelFrame.contains(point) else { return false }
        // A corner radius larger than half a side is not a valid rounded rectangle.
        let radius = min(StackMetrics.Panel.cornerRadius, panelFrame.width / 2, panelFrame.height / 2)
        return CGPath(roundedRect: panelFrame, cornerWidth: radius, cornerHeight: radius, transform: nil).contains(point)
    }

    func isOnResizeEdge(_ point: CGPoint) -> Bool {
        isInsidePanel(point) && point.y >= panelFrame.maxY - StackMetrics.Panel.resizeEdgeHeight
    }

    /// - Parameter isOverControl: Whether a button is under the point; only the caller can tell.
    func target(at point: CGPoint, isOverControl: Bool) -> StackPointerTarget {
        if isOnResizeEdge(point) { return .resize }
        guard isInsidePanel(point), row(at: point) == nil, !isOverControl else { return .passThrough }
        return .move
    }

    /// The row whose card, or whose delete button, is under the point. Cards scrolled under the
    /// header do not count; the delete button sticks out of its card and may reach a little
    /// further up.
    func row(at point: CGPoint) -> StackRow.ID? {
        let headerHeight = StackMetrics.Header.height
        let visibleList = listFrame.divided(atDistance: headerHeight, from: .minYEdge).remainder
        let deleteButtonArea = listFrame
            .divided(atDistance: headerHeight - StackMetrics.Card.deleteButtonReach, from: .minYEdge).remainder

        return cardFrames.first { _, frame in
            (visibleList.contains(point) && frame.contains(point))
                || (deleteButtonArea.contains(point) && Self.deleteButtonFrame(forCard: frame).contains(point))
        }?.key
    }

    /// Whether a row — its card and the delete button that sticks out of its top — starts above
    /// the part of the list the header leaves in view. `false` for a row with no card.
    func isScrolledUnderHeader(_ rowID: StackRow.ID) -> Bool {
        guard let frame = cardFrames[rowID] else { return false }
        return frame.minY - StackMetrics.Card.deleteButtonOverhang < listFrame.minY + StackMetrics.Header.height
    }

    /// The delete button overhangs the card's top-right corner.
    static func deleteButtonFrame(forCard frame: CGRect) -> CGRect {
        let side = StackMetrics.Card.deleteButtonSide
        let overhang = StackMetrics.Card.deleteButtonOverhang
        return CGRect(x: frame.maxX + overhang - side, y: frame.minY - overhang, width: side, height: side)
    }
}
