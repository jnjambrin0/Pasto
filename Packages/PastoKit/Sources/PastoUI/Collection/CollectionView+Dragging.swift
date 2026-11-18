import AppKit

/// The numbers of dragging.
nonisolated enum DraggingMetrics {
    /// How far the pointer has to travel from the press before a drag starts.
    static let startDistance: CGFloat = 3
    /// The image of a cell dragged on its own is see-through; several are dragged opaque.
    static let singleItemImageOpacity: CGFloat = 0.7
    /// After a drag that ends inside the window the application is activated again, this late.
    static let reactivationDelay: TimeInterval = 1

    static let cursorWidth: CGFloat = 4
    static let cursorCornerRadius: CGFloat = 2

    /// Within this distance of either end, a reordering drag scrolls the strip…
    static let autoscrollBand: CGFloat = 30
    /// …by up to this much per update, the closer to the edge the faster.
    static let autoscrollMaximumStep: CGFloat = 15
}

// MARK: - Source

extension CollectionView: NSDraggingSource {
    /// Drags the whole selection, in the order it was made. Every selected cell contributes the
    /// dragging items its writers ask for, all with the cell's frame and picture; a cell that is
    /// scrolled out of view has no picture.
    func beginDraggingSelection(with event: NSEvent) {
        guard let delegate else { return }
        let indexes = selection.indexes
        let writers = delegate.collectionView(self, pasteboardWritersForCellsAt: indexes)
        let opacity = indexes.count == 1 ? DraggingMetrics.singleItemImageOpacity : 1

        let items = zip(indexes, writers).flatMap { index, writers -> [NSDraggingItem] in
            let frame = convert(contentLayout.frame(forCellAt: index), from: scrollContainer.documentView)
            let image = cell(at: index).map { Self.draggingImage(of: $0, opacity: opacity) }
            return writers.map { writer in
                let item = NSDraggingItem(pasteboardWriter: writer)
                item.setDraggingFrame(frame, contents: image)
                return item
            }
        }
        guard !items.isEmpty else { return }

        let session = beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = event.modifierFlags.contains(.control) ? .stack : .pile
    }

    /// A picture of the cell as it is, at its own size, without the selection ring.
    private static func draggingImage(of cell: CollectionViewCell, opacity: CGFloat) -> NSImage {
        let wasSelected = cell.isSelected
        cell.isSelected = false
        defer { cell.isSelected = wasSelected }

        let image = NSImage(size: cell.bounds.size)
        guard let bitmap = cell.bitmapImageRepForCachingDisplay(in: cell.bounds) else { return image }
        cell.cacheDisplay(in: cell.bounds, to: bitmap)
        image.lockFocus()
        bitmap.draw(
            in: NSRect(origin: .zero, size: cell.bounds.size), from: .zero, operation: .sourceOver,
            fraction: opacity, respectFlipped: true, hints: nil
        )
        image.unlockFocus()
        return image
    }

    /// Other applications get a copy; inside this one a drag moves.
    public func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : .move
    }

    public func draggingSession(_ session: NSDraggingSession, movedTo screenPoint: NSPoint) {
        draggingSessionDidMove(session, to: screenPoint)
    }

    public func draggingSession(_ session: NSDraggingSession, endedAt screenPoint: NSPoint, operation: NSDragOperation) {
        guard window?.frame.contains(screenPoint) == true else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + DraggingMetrics.reactivationDelay) {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}

// MARK: - Destination: reordering

extension CollectionView {
    /// Only a drag that started in this very collection is taken, and only to reorder it.
    private func accepts(_ sender: any NSDraggingInfo) -> Bool {
        isReorderingEnabled && sender.draggingSource as AnyObject? === self
    }

    override open func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        accepts(sender) ? .move : []
    }

    override open func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        guard accepts(sender) else { return [] }
        placeInsertionCursor(for: sender)
        autoscroll(for: sender)
        return .move
    }

    override open func draggingEnded(_ sender: any NSDraggingInfo) {
        insertionCursor?.removeFromSuperview()
    }

    override open func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        insertionCursor?.removeFromSuperview()
        guard accepts(sender), let target = dropTarget(for: sender) else { return false }
        delegate?.collectionView(self, moveCellsAt: selection.indexes, to: target.destination)
        return true
    }

    /// Where a drop at the pointer would go: next to the visible cell whose frame, widened by
    /// one spacing on each side, holds the pointer — in front of it from its first half, behind
    /// it from its second. `nil` when the pointer is over no cell.
    private func dropTarget(for sender: any NSDraggingInfo) -> (destination: Int, cellFrame: CGRect, isInFront: Bool)? {
        let point = scrollContainer.documentView.convert(sender.draggingLocation, from: nil)
        let spacing = layoutConfiguration.interitemSpacing
        for index in visibleCellsByIndex.keys.sorted() {
            let frame = contentLayout.frame(forCellAt: index)
            guard frame.insetBy(dx: -spacing, dy: 0).contains(point) else { continue }
            let isInFront = point.x < frame.midX
            return (isInFront ? index : index + 1, frame, isInFront)
        }
        return nil
    }

    /// The cursor sits in the middle of the gap the cells would be dropped in. Away from any
    /// cell it stays where it was.
    private func placeInsertionCursor(for sender: any NSDraggingInfo) {
        guard let target = dropTarget(for: sender) else { return }
        let cursor = insertionCursor ?? InsertionCursorView(frame: .zero)
        insertionCursor = cursor
        if cursor.superview == nil {
            scrollContainer.documentView.addSubview(cursor)
        }
        let gapCentre = target.isInFront
            ? target.cellFrame.minX - layoutConfiguration.interitemSpacing / 2
            : target.cellFrame.maxX + layoutConfiguration.interitemSpacing / 2
        cursor.frame = CGRect(
            x: gapCentre - DraggingMetrics.cursorWidth / 2,
            y: layoutConfiguration.bottom,
            width: DraggingMetrics.cursorWidth,
            height: contentLayout.cellSide
        )
    }

    private func autoscroll(for sender: any NSDraggingInfo) {
        let limits = convert(bounds, to: nil)
        let step = Self.autoscrollStep(pointerX: sender.draggingLocation.x, from: limits.minX, to: limits.maxX)
        guard step != 0 else { return }
        let visible = scrollContainer.visibleDocumentRect
        let furthest = max(contentLayout.documentSize.width - visible.width, 0)
        let offset = CGPoint(x: min(max(visible.minX + step, 0), furthest), y: visible.minY)
        scrollContainer.setContentOffset(offset, animated: false)
    }

    /// How far one update of a drag scrolls a strip that spans `minX...maxX`: nothing in the
    /// middle, and proportionally more the closer the pointer is to an end.
    nonisolated static func autoscrollStep(pointerX: CGFloat, from minX: CGFloat, to maxX: CGFloat) -> CGFloat {
        let band = DraggingMetrics.autoscrollBand
        let reach = { (distance: CGFloat) in DraggingMetrics.autoscrollMaximumStep * (band - distance) / band }
        if pointerX < minX + band {
            return -reach(max(pointerX - minX, 0))
        }
        if pointerX > maxX - band {
            return reach(max(maxX - pointerX, 0))
        }
        return 0
    }
}

/// The bar that marks where dragged cells would land.
final class InsertionCursorView: LayerBackedView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        layer?.cornerRadius = DraggingMetrics.cursorCornerRadius
    }

    override func updateLayerColors() {
        layer?.backgroundColor = NSColor.keyboardFocusIndicatorColor.cgColor
    }
}
