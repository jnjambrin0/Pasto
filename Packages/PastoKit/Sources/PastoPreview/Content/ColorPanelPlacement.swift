import CoreGraphics

/// Where the system colour panel goes while a colour is edited.
nonisolated enum ColorPanelPlacement {
    /// Beside the editing window and centred on it vertically: to its right when the screen has
    /// room for the panel and a gap on each side of it, to its left otherwise.
    static func origin(windowFrame: CGRect, panelSize: CGSize, screenWidth: CGFloat) -> CGPoint {
        let gap = PreviewMetrics.colorPanelGap
        let fitsOnTheRight = screenWidth - windowFrame.maxX >= panelSize.width + 2 * gap
        return CGPoint(
            x: fitsOnTheRight ? windowFrame.maxX + gap : windowFrame.minX - gap - panelSize.width,
            y: windowFrame.minY - (panelSize.height - windowFrame.height) / 2
        )
    }
}
