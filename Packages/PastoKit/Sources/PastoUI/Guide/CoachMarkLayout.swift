import CoreGraphics

/// Where a coach mark goes next to the element it explains.
/// Coordinates are those of the container, with y upwards, as in AppKit.
public nonisolated enum CoachMarkLayout {
    public enum Side: Sendable, Equatable {
        case below, above, trailing, leading
    }

    /// The frame of a mark of `size` beside `anchor`: on the first of `sides` where it fits whole
    /// inside `container` less `margin`, centred on the anchor along that side and kept inside.
    /// When it fits on none, on the first side, pushed inside the container as far as it goes.
    public static func frame(
        size: CGSize,
        anchor: CGRect,
        in container: CGRect,
        sides: [Side],
        gap: CGFloat,
        margin: CGFloat
    ) -> (frame: CGRect, side: Side) {
        let bounds = container.insetBy(dx: margin, dy: margin)
        for side in sides {
            let frame = candidate(size: size, anchor: anchor, side: side, gap: gap, bounds: bounds)
            if bounds.contains(frame) {
                return (frame, side)
            }
        }
        let side = sides.first ?? .below
        let frame = candidate(size: size, anchor: anchor, side: side, gap: gap, bounds: bounds)
        return (pushedInside(frame, bounds: bounds), side)
    }

    private static func candidate(size: CGSize, anchor: CGRect, side: Side, gap: CGFloat, bounds: CGRect) -> CGRect {
        var origin: CGPoint
        switch side {
        case .below:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.minY - gap - size.height)
        case .above:
            origin = CGPoint(x: anchor.midX - size.width / 2, y: anchor.maxY + gap)
        case .trailing:
            origin = CGPoint(x: anchor.maxX + gap, y: anchor.midY - size.height / 2)
        case .leading:
            origin = CGPoint(x: anchor.minX - gap - size.width, y: anchor.midY - size.height / 2)
        }
        // Along the side, the mark slides to stay inside.
        switch side {
        case .below, .above:
            origin.x = clamp(origin.x, bounds.minX, bounds.maxX - size.width)
        case .trailing, .leading:
            origin.y = clamp(origin.y, bounds.minY, bounds.maxY - size.height)
        }
        return CGRect(origin: CGPoint(x: origin.x.rounded(), y: origin.y.rounded()), size: size)
    }

    private static func pushedInside(_ frame: CGRect, bounds: CGRect) -> CGRect {
        CGRect(
            x: clamp(frame.minX, bounds.minX, bounds.maxX - frame.width).rounded(),
            y: clamp(frame.minY, bounds.minY, bounds.maxY - frame.height).rounded(),
            width: frame.width,
            height: frame.height
        )
    }

    /// `value` within `lower…upper`; `lower` wins when the range is empty.
    private static func clamp(_ value: CGFloat, _ lower: CGFloat, _ upper: CGFloat) -> CGFloat {
        max(lower, min(value, upper))
    }
}
