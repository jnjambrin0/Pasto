import AppKit

/// The checkerboard behind images: it shows through transparent pixels and in the bands left
/// when an image does not fill its frame.
///
/// Only every other square is painted; the card's background shows through the rest. The
/// squares are counted from the bottom-left corner, which holds a painted one, so the top row
/// is cut when the height is not a multiple of the square. The view draws into its layer once
/// per size, so scrolling costs nothing.
public final class CheckerboardView: NSView {
    private static let squareSide: CGFloat = 8

    override public init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layerContentsRedrawPolicy = .duringViewResize
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("CheckerboardView is created in code")
    }

    override public func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        needsDisplay = true
    }

    override public func draw(_ dirtyRect: NSRect) {
        let side = Self.squareSide
        CardColor.checkerSquare.setFill()

        let rows = Int(dirtyRect.minY / side)...Int(dirtyRect.maxY / side)
        let columns = Int(dirtyRect.minX / side)...Int(dirtyRect.maxX / side)
        for row in rows {
            for column in columns where (row + column).isMultiple(of: 2) {
                NSRect(x: CGFloat(column) * side, y: CGFloat(row) * side, width: side, height: side).fill(using: .sourceOver)
            }
        }
    }
}
