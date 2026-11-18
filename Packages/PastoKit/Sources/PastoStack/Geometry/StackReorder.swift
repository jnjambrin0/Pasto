import CoreGraphics

/// Where a row being dragged over the list belongs.
nonisolated enum StackReorder {
    /// The index a row dragged to `pointerY` goes to: below every card whose middle is above the
    /// pointer, so the row passes a neighbour when the pointer crosses the neighbour's middle.
    ///
    /// - Parameter cardFrames: The cards the row is placed among, in the same coordinate space
    ///   as `pointerY`, y growing downwards. A row of the stack being moved is placed among the
    ///   others, without its own card; something dragged in from elsewhere, among all of them.
    static func index(forPointerY pointerY: CGFloat, among cardFrames: [CGRect]) -> Int {
        cardFrames.count { $0.midY < pointerY }
    }
}
