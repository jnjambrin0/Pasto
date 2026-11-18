import CoreGraphics

/// A window as the window server lists it, with its frame already in screen coordinates where y
/// grows upwards.
nonisolated struct SnapWindow: Equatable {
    var frame: CGRect
    var layer: Int
    var alpha: Double
    var number: Int
}

/// Works out the guides of a drag, once, when it starts.
nonisolated enum SnapGuideBuilder {
    /// - Parameters:
    ///   - screens: The visible frame of every screen.
    ///   - windows: The windows on screen, front to back.
    ///   - ownWindowNumber: The stack's own window, which is no guide for itself.
    /// - Returns: The screens' edges first, then the windows' from front to back: when several
    ///   guides could catch the panel, the first one does.
    static func guides(screens: [CGRect], windows: [SnapWindow], ownWindowNumber: Int) -> [SnapGuide] {
        let screenGuides = screens.flatMap { screen in
            SnapEdge.allCases.map { edge in
                SnapGuide(
                    edge: edge,
                    line: screen.position(of: edge),
                    span: screen.extent(along: edge.axis.other),
                    source: .screen(screen)
                )
            }
        }

        let accepted = windows.filter { window in
            window.layer == 0 && window.alpha >= StackMetrics.Snap.minimumWindowAlpha && window.number != ownWindowNumber
        }
        var windowGuides: [SnapGuide] = []
        for (index, window) in accepted.enumerated() {
            let windowsInFront = accepted[..<index].map(\.frame)
            for edge in SnapEdge.allCases {
                let line = window.frame.position(of: edge)
                let visible = visibleSpans(of: edge, of: window.frame, behind: windowsInFront)
                windowGuides += visible.map { SnapGuide(edge: edge, line: line, span: $0, source: .window(window.frame)) }
            }
        }
        return screenGuides + windowGuides
    }

    /// The stretches of an edge that no window in front covers. A window covers the edge where
    /// the edge runs strictly inside it; one that merely touches it hides nothing.
    private static func visibleSpans(of edge: SnapEdge, of frame: CGRect, behind windowsInFront: [CGRect]) -> [ClosedRange<CGFloat>] {
        let line = frame.position(of: edge)
        var spans = [frame.extent(along: edge.axis.other)]
        for cover in windowsInFront {
            let across = cover.extent(along: edge.axis)
            guard across.lowerBound < line, line < across.upperBound else { continue }
            let hidden = cover.extent(along: edge.axis.other)
            spans = spans.flatMap { subtract(hidden, from: $0) }
        }
        return spans
    }

    private static func subtract(_ hidden: ClosedRange<CGFloat>, from span: ClosedRange<CGFloat>) -> [ClosedRange<CGFloat>] {
        guard hidden.overlaps(span) else { return [span] }
        var pieces: [ClosedRange<CGFloat>] = []
        if span.lowerBound < hidden.lowerBound {
            pieces.append(span.lowerBound...hidden.lowerBound)
        }
        if hidden.upperBound < span.upperBound {
            pieces.append(hidden.upperBound...span.upperBound)
        }
        return pieces
    }
}
