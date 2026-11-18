import CoreGraphics

/// The two directions the panel moves in. Snapping treats them independently.
nonisolated enum SnapAxis: CaseIterable {
    case horizontal
    case vertical

    var other: SnapAxis {
        switch self {
        case .horizontal: .vertical
        case .vertical: .horizontal
        }
    }
}

/// An edge of a rectangle in screen coordinates, where y grows upwards.
nonisolated enum SnapEdge: CaseIterable {
    case left
    case right
    case bottom
    case top

    /// The axis along which this edge's position is measured.
    var axis: SnapAxis {
        switch self {
        case .left, .right: .horizontal
        case .bottom, .top: .vertical
        }
    }

    var opposite: SnapEdge {
        switch self {
        case .left: .right
        case .right: .left
        case .bottom: .top
        case .top: .bottom
        }
    }

    /// Whether this is the far edge of its axis (right, top) rather than the near one.
    var isFarEdge: Bool {
        self == .right || self == .top
    }
}

/// A line the panel's edges can catch on while it is dragged: an edge of a screen, or a visible
/// stretch of an edge of another window.
nonisolated struct SnapGuide: Equatable {
    enum Source: Equatable {
        case screen(CGRect)
        case window(CGRect)
    }

    /// Which edge of the source this is.
    var edge: SnapEdge
    /// The edge's position on its axis.
    var line: CGFloat
    /// The stretch of the line the guide covers, on the other axis.
    var span: ClosedRange<CGFloat>
    var source: Source
}

/// A way for the panel to sit on a guide: one of its edges on a line.
nonisolated struct SnapCandidate: Equatable {
    var panelEdge: SnapEdge
    var line: CGFloat
    var guide: SnapGuide
}

nonisolated extension SnapGuide {
    /// A screen edge takes the same edge of the panel, which stays inside the screen. A window
    /// edge takes the same edge too (flush with the window) and the opposite one a point outside
    /// it (next to the window).
    var candidates: [SnapCandidate] {
        let flush = SnapCandidate(panelEdge: edge, line: line, guide: self)
        switch source {
        case .screen:
            return [flush]
        case .window:
            let gap = edge.isFarEdge ? StackMetrics.Snap.windowGap : -StackMetrics.Snap.windowGap
            return [flush, SnapCandidate(panelEdge: edge.opposite, line: line + gap, guide: self)]
        }
    }
}

nonisolated extension CGRect {
    func position(of edge: SnapEdge) -> CGFloat {
        switch edge {
        case .left: minX
        case .right: maxX
        case .bottom: minY
        case .top: maxY
        }
    }

    /// The rectangle's extent along `axis`.
    func extent(along axis: SnapAxis) -> ClosedRange<CGFloat> {
        switch axis {
        case .horizontal: minX...maxX
        case .vertical: minY...maxY
        }
    }
}

nonisolated extension CGPoint {
    subscript(axis: SnapAxis) -> CGFloat {
        get {
            switch axis {
            case .horizontal: x
            case .vertical: y
            }
        }
        set {
            switch axis {
            case .horizontal: x = newValue
            case .vertical: y = newValue
            }
        }
    }
}
