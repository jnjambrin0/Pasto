import CoreGraphics
import Observation

/// What the panel's views and its window tell each other: where things are, what the pointer is
/// over and which row is being dragged.
///
/// Every rectangle is in the coordinate space of the view that fills the window, y growing
/// downwards.
@Observable
final class StackPanelState {
    /// The tallest the panel may get, header included.
    var heightLimit: CGFloat
    var hoveredRowID: StackRow.ID?
    /// True while the pointer is moving or resizing the panel.
    var isTrackingPanel = false
    /// The row being dragged, from the moment its dragging session opens until it ends.
    var draggedRowID: StackRow.ID?
    /// The row whose card is off the list — following the pointer, or gliding back to its slot
    /// after the drag. The list keeps the slot, empty.
    var liftedRowID: StackRow.ID?
    /// Where something dragged in from elsewhere would be dropped, as an index among the rows;
    /// the list opens a gap there.
    var dropIndex: Int?

    // Geometry the views report and only the window reads: observing it would redraw the views
    // on every scroll step.
    @ObservationIgnored var panelFrame = CGRect.zero {
        didSet {
            if panelFrame != oldValue { onPanelFrameChange?() }
        }
    }
    /// Called when the visible panel changes size or place inside the window.
    @ObservationIgnored var onPanelFrameChange: (() -> Void)?
    @ObservationIgnored var listFrame = CGRect.zero
    @ObservationIgnored var cardFrames: [StackRow.ID: CGRect] = [:] {
        didSet { onCardFramesChange?() }
    }

    /// Called whenever a card moves — the list scrolled or changed — so that what is under a
    /// pointer that did not move can be worked out again.
    @ObservationIgnored var onCardFramesChange: (() -> Void)?

    init(heightLimit: CGFloat) {
        self.heightLimit = heightLimit
    }

    /// The row that shows its delete button: the one under the pointer, unless the pointer is
    /// busy dragging a row or the panel.
    var highlightedRowID: StackRow.ID? {
        draggedRowID == nil && liftedRowID == nil && !isTrackingPanel ? hoveredRowID : nil
    }

    var hitTest: StackHitTest {
        StackHitTest(panelFrame: panelFrame, listFrame: listFrame, cardFrames: cardFrames)
    }
}
