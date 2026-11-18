import AppKit

/// A scroll view for a horizontal strip that scrolls sideways with a plain vertical mouse
/// wheel, without the user holding Shift.
final class NoShiftHorizontalScrollView: NSScrollView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        hasHorizontalScroller = false
        drawsBackground = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("NoShiftHorizontalScrollView is created in code")
    }

    override class var isCompatibleWithResponsiveScrolling: Bool { true }

    override func scrollWheel(with event: NSEvent) {
        // Only purely vertical events are rewritten; anything with a horizontal component is
        // already what the strip wants.
        guard event.scrollingDeltaX == 0, event.scrollingDeltaY != 0,
              let horizontal = event.cgEvent?.copy()
        else {
            super.scrollWheel(with: event)
            return
        }
        horizontal.setIntegerValueField(.scrollWheelEventDeltaAxis2, value: Int64(event.scrollingDeltaY))
        horizontal.setIntegerValueField(.scrollWheelEventDeltaAxis1, value: 0)
        super.scrollWheel(with: NSEvent(cgEvent: horizontal) ?? event)
    }
}
