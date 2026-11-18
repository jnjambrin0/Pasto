import CoreGraphics

/// Geometry of the collection: one row of square cells whose side follows the collection's
/// height, in the document view's (bottom-left origin) coordinate space.
public nonisolated struct CollectionContentLayout: Sendable, Equatable {
    public struct Configuration: Sendable, Equatable {
        public var top: CGFloat
        public var left: CGFloat
        public var bottom: CGFloat
        public var right: CGFloat
        public var interitemSpacing: CGFloat

        public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat, interitemSpacing: CGFloat) {
            self.top = top
            self.left = left
            self.bottom = bottom
            self.right = right
            self.interitemSpacing = interitemSpacing
        }
    }

    public var configuration: Configuration
    /// Size of the collection view.
    public var boundsSize: CGSize
    public var cellCount: Int

    public init(configuration: Configuration, boundsSize: CGSize, cellCount: Int) {
        self.configuration = configuration
        self.boundsSize = boundsSize
        self.cellCount = cellCount
    }

    /// Cells are square: as tall as the collection minus the vertical insets.
    public var cellSide: CGFloat {
        max(boundsSize.height - configuration.top - configuration.bottom, 0)
    }

    /// Distance between the leading edges of consecutive cells.
    public var stride: CGFloat {
        cellSide + configuration.interitemSpacing
    }

    public func frame(forCellAt index: Int) -> CGRect {
        CGRect(
            x: configuration.left + CGFloat(index) * stride,
            y: configuration.bottom,
            width: cellSide,
            height: cellSide
        )
    }

    public var contentWidth: CGFloat {
        let cells = CGFloat(cellCount) * cellSide + CGFloat(max(cellCount - 1, 0)) * configuration.interitemSpacing
        return configuration.left + cells + configuration.right
    }

    /// The document is never smaller than the collection itself.
    public var documentSize: CGSize {
        let content = CGSize(width: contentWidth, height: boundsSize.height)
        return content.width * content.height > boundsSize.width * boundsSize.height ? content : boundsSize
    }

    /// The cells that exist for a visible rectangle. There is no preloading margin; a cell's
    /// span includes the gap after it, so it stays alive while that gap is still in view.
    public func visibleIndexes(in rect: CGRect) -> ClosedRange<Int>? {
        guard cellCount > 0, stride > 0, !rect.isEmpty else { return nil }
        let last = cellCount - 1
        let lower = Int(((rect.minX - configuration.left) / stride).rounded(.down))
        let upper = Int(((rect.maxX - configuration.left) / stride).rounded(.down))
        let first = min(max(lower, 0), last)
        return first...max(min(max(upper, 0), last), first)
    }

    /// The cell whose frame contains `point`, or nil in a gap or outside the row.
    public func index(at point: CGPoint) -> Int? {
        guard cellCount > 0, stride > 0, point.x >= configuration.left else { return nil }
        let index = Int((point.x - configuration.left) / stride)
        guard index < cellCount, frame(forCellAt: index).contains(point) else { return nil }
        return index
    }
}
