import CoreGraphics

/// The arithmetic of dragging a tab to a new position.
nonisolated enum TabBarReorder {
    /// The position the dragged tab takes as the pointer moves over the others.
    ///
    /// `cellFrames` are the tabs as they are laid out now, with the dragged one, invisible, at
    /// `currentIndex`; `pointer` is in the same coordinates. The tab under the pointer gives way
    /// once the pointer passes its middle, coming from the side the dragged tab is on. Over the
    /// dragged tab's own gap, or away from every tab, nothing changes. Every position is offered:
    /// the clipboard history moves like any other tab.
    static func destinationIndex(cellFrames: [CGRect], currentIndex: Int, pointer: CGPoint) -> Int {
        guard let hovered = cellFrames.firstIndex(where: { $0.contains(pointer) }), hovered != currentIndex else {
            return currentIndex
        }
        let midX = cellFrames[hovered].midX
        if currentIndex < hovered {
            return pointer.x > midX ? hovered : hovered - 1
        } else {
            return pointer.x < midX ? hovered : hovered + 1
        }
    }

    /// `elements` with the one at `source` taken out and put back at `destination`.
    static func moving<Element>(_ elements: [Element], from source: Int, to destination: Int) -> [Element] {
        var result = elements
        result.insert(result.remove(at: source), at: destination)
        return result
    }
}
