import AppKit
import PastoCore

/// The row of colour swatches at the bottom of a pinboard tab's context menu.
final class PinboardColorMenuItemView: NSView {
    private enum Metrics {
        static let rowHeight: CGFloat = 26
        static let swatchDiameter: CGFloat = 14
        /// From one swatch's centre to the next.
        static let swatchPitch: CGFloat = 24
        /// Each swatch sits in a square cell this wide, which is what the pointer hits; the 2 pt
        /// between two cells belong to neither.
        static let cellSide: CGFloat = 22
        /// Space left on each side of the row at its natural width.
        static let sideInset: CGFloat = 14
        /// The ring around the selected swatch, and around the one under the pointer, fills its
        /// cell: a 1 pt edge in the label colour at `ringEdgeOpacity` — around the selected one,
        /// over a well of the text background — all of it drawn at `ringOpacity`.
        static let ringEdgeWidth: CGFloat = 1
        static let ringEdgeOpacity: CGFloat = 0.26
        static let ringOpacity: CGFloat = 0.6
    }

    private let selectedColor: PinboardColor
    private let onPick: (PinboardColor) -> Void

    /// The swatch under the pointer.
    private var hoveredIndex: Int? {
        didSet {
            if hoveredIndex != oldValue { needsDisplay = true }
        }
    }
    private var cellTrackingAreas: [NSTrackingArea] = []

    /// The swatches as assistive technologies see them, in order.
    private nonisolated let swatchElements: [SwatchAccessibilityElement]

    init(selectedColor: PinboardColor, onPick: @escaping (PinboardColor) -> Void) {
        self.selectedColor = selectedColor
        self.onPick = onPick
        swatchElements = PinboardColor.allCases.enumerated().map { index, color in
            SwatchAccessibilityElement(index: index, label: ToolbarStrings.colorName(color))
        }
        let count = CGFloat(PinboardColor.allCases.count)
        let width = (count - 1) * Metrics.swatchPitch + Metrics.swatchDiameter + 2 * Metrics.sideInset
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: Metrics.rowHeight))
        // The row stays centred if longer titles make the menu wider.
        autoresizingMask = [.width]
        for element in swatchElements {
            element.row = self
            element.setAccessibilityParent(self)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("PinboardColorMenuItemView is created in code")
    }

    /// Centre of the swatch at `index`: the row is centred in the menu item.
    private func swatchCentre(at index: Int) -> NSPoint {
        let span = CGFloat(PinboardColor.allCases.count - 1) * Metrics.swatchPitch
        return NSPoint(x: bounds.midX - span / 2 + CGFloat(index) * Metrics.swatchPitch, y: bounds.midY)
    }

    private func cellFrame(at index: Int) -> NSRect {
        let centre = swatchCentre(at: index)
        let side = Metrics.cellSide
        return NSRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
    }

    private func circle(at centre: NSPoint, diameter: CGFloat) -> NSBezierPath {
        NSBezierPath(ovalIn: NSRect(x: centre.x - diameter / 2, y: centre.y - diameter / 2, width: diameter, height: diameter))
    }

    // MARK: - Drawing

    override func draw(_ dirtyRect: NSRect) {
        for (index, color) in PinboardColor.allCases.enumerated() {
            let centre = swatchCentre(at: index)
            if color == selectedColor {
                drawRing(at: centre, withWell: true)
            } else if index == hoveredIndex {
                drawRing(at: centre, withWell: false)
            }
            color.displayColor.setFill()
            circle(at: centre, diameter: Metrics.swatchDiameter).fill()
        }
    }

    /// The well and the edge are drawn opaque to each other, then faded together.
    private func drawRing(at centre: NSPoint, withWell: Bool) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.setAlpha(Metrics.ringOpacity)
        context.beginTransparencyLayer(auxiliaryInfo: nil)
        if withWell {
            NSColor.textBackgroundColor.setFill()
            circle(at: centre, diameter: Metrics.cellSide).fill()
        }
        // The edge runs along the inside of the cell.
        let edge = circle(at: centre, diameter: Metrics.cellSide - Metrics.ringEdgeWidth)
        edge.lineWidth = Metrics.ringEdgeWidth
        NSColor.labelColor.withAlphaComponent(Metrics.ringEdgeOpacity).setStroke()
        edge.stroke()
        context.endTransparencyLayer()
        context.restoreGState()
    }

    // MARK: - Mouse

    /// One area per cell, following the pointer while the menu is open.
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        cellTrackingAreas.forEach(removeTrackingArea)
        cellTrackingAreas = PinboardColor.allCases.indices.map { index in
            NSTrackingArea(
                rect: cellFrame(at: index),
                options: [.mouseEnteredAndExited, .activeAlways],
                owner: self,
                userInfo: [Self.cellIndexKey: index]
            )
        }
        cellTrackingAreas.forEach(addTrackingArea)
    }

    private static let cellIndexKey = "cellIndex"

    private func cellIndex(of event: NSEvent) -> Int? {
        event.trackingArea?.userInfo?[Self.cellIndexKey] as? Int
    }

    override func mouseEntered(with event: NSEvent) {
        if let index = cellIndex(of: event) {
            hoveredIndex = index
        }
    }

    override func mouseExited(with event: NSEvent) {
        if let index = cellIndex(of: event), index == hoveredIndex {
            hoveredIndex = nil
        }
    }

    /// Chosen on release, like any menu item, so a press can still be dragged away. Only a cell
    /// chooses: the gaps between them do not.
    override func mouseUp(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        guard let index = PinboardColor.allCases.indices.first(where: { cellFrame(at: $0).contains(point) }) else { return }
        pick(at: index)
    }

    private func pick(at index: Int) {
        enclosingMenuItem?.menu?.cancelTracking()
        onPick(PinboardColor.allCases[index])
    }

    // MARK: - Accessibility

    // The row is a radio group named "Color" and each swatch one of its radio buttons, named
    // after its colour, so that the colours are not told apart by their colour alone.

    override func isAccessibilityElement() -> Bool { true }

    override func accessibilityRole() -> NSAccessibility.Role? { .radioGroup }

    override func accessibilityLabel() -> String? { ToolbarStrings.pinboardColor }

    override func accessibilityChildren() -> [Any]? { swatchElements }

    nonisolated override func accessibilityHitTest(_ point: NSPoint) -> Any? {
        swatchElements.first { $0.accessibilityFrame().contains(point) } ?? self
    }

    /// One swatch, for assistive technologies: where it is on screen, whether it is the
    /// pinboard's colour, and choosing it.
    ///
    /// AppKit declares accessibility elements without an actor, although it only uses them on
    /// the main thread; hence a `nonisolated` type that assumes it.
    private nonisolated final class SwatchAccessibilityElement: NSAccessibilityElement, @unchecked Sendable {
        weak var row: PinboardColorMenuItemView?
        private let index: Int

        init(index: Int, label: String) {
            self.index = index
            super.init()
            setAccessibilityRole(.radioButton)
            setAccessibilityLabel(label)
        }

        override func accessibilityFrame() -> NSRect {
            let (row, index) = (row, index)
            return MainActor.assumeIsolated {
                guard let row else { return .zero }
                return NSAccessibility.screenRect(fromView: row, rect: row.cellFrame(at: index))
            }
        }

        private var isSelected: Bool {
            let (row, index) = (row, index)
            return MainActor.assumeIsolated {
                row?.selectedColor == PinboardColor.allCases[index]
            }
        }

        override func accessibilityValue() -> Any? { NSNumber(value: isSelected) }

        override func isAccessibilitySelected() -> Bool { isSelected }

        override func accessibilityPerformPress() -> Bool {
            let (row, index) = (row, index)
            return MainActor.assumeIsolated {
                guard let row else { return false }
                row.pick(at: index)
                return true
            }
        }
    }
}
