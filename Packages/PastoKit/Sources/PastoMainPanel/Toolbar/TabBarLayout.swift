import CoreGraphics

/// Where the tabs go inside the tab bar's scrolling content.
nonisolated struct TabBarLayout: Equatable {
    /// Cell frames in the content's coordinates, in display order.
    let cellFrames: [CGRect]
    /// Size of the scrolling content, insets included.
    let contentSize: CGSize

    init(cellWidths: [CGFloat]) {
        var frames: [CGRect] = []
        var x = TabBarMetrics.horizontalContentInset
        for width in cellWidths {
            frames.append(CGRect(
                x: x,
                y: TabBarMetrics.verticalContentInset,
                width: width,
                height: TabBarMetrics.cellHeight
            ))
            x += width + TabBarMetrics.cellSpacing
        }
        let lastCellEnd = frames.last?.maxX ?? TabBarMetrics.horizontalContentInset
        cellFrames = frames
        contentSize = CGSize(
            width: lastCellEnd + TabBarMetrics.horizontalContentInset,
            height: TabBarMetrics.scrollHeight
        )
    }

    /// The width at which the tab bar shows every tab: its content plus the two edge overlays,
    /// which sit outside the scrolling area.
    var intrinsicWidth: CGFloat {
        contentSize.width + 2 * TabBarMetrics.edgeOverlayWidth
    }

    /// Width of the label's box for text `textWidth` wide.
    static func labelWidth(textWidth: CGFloat) -> CGFloat {
        min(textWidth.rounded(.up) + TabBarMetrics.labelSlack, TabBarMetrics.maximumLabelWidth)
    }

    /// Width of a cell: icon, gap, label and the margins around them.
    static func cellWidth(iconSide: CGFloat, textWidth: CGFloat) -> CGFloat {
        TabBarMetrics.iconLeadingInset + iconSide + TabBarMetrics.iconToLabelSpacing
            + labelWidth(textWidth: textWidth) + TabBarMetrics.labelTrailingInset
    }

    /// The horizontal scroll offset that shows `cellFrame` with `TabBarMetrics.revealMargin` to
    /// spare on each side, moving as little as possible from `currentOffset`.
    func scrollOffset(revealing cellFrame: CGRect, from currentOffset: CGFloat, visibleWidth: CGFloat) -> CGFloat {
        scrollOffset(
            showing: cellFrame.insetBy(dx: -TabBarMetrics.revealMargin, dy: 0),
            from: currentOffset,
            visibleWidth: visibleWidth
        )
    }

    /// The horizontal scroll offset that shows the trailing edge of `cellFrame`, a tab whose name
    /// is being typed, moving as little as possible from `currentOffset`.
    func scrollOffset(revealingTrailingEdgeOf cellFrame: CGRect, from currentOffset: CGFloat, visibleWidth: CGFloat) -> CGFloat {
        scrollOffset(
            showing: CGRect(x: cellFrame.maxX, y: cellFrame.minY, width: 1, height: cellFrame.height),
            from: currentOffset,
            visibleWidth: visibleWidth
        )
    }

    private func scrollOffset(showing target: CGRect, from currentOffset: CGFloat, visibleWidth: CGFloat) -> CGFloat {
        var offset = currentOffset
        if target.maxX > offset + visibleWidth {
            offset = target.maxX - visibleWidth
        }
        // Checked last so that the leading edge wins when the cell is wider than the visible area.
        if target.minX < offset {
            offset = target.minX
        }
        return min(max(offset, 0), max(contentSize.width - visibleWidth, 0))
    }
}
