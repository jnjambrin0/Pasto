import AppKit
import PastoCoreUI
import PastoUI

/// Draws cards into bitmaps without putting anything on screen: the cells live in a window that
/// is never ordered in, which is enough for them to resolve colours, lay out and draw.
final class CardRenderer {
    /// Room around the card for the selection ring and the shadow.
    private static let margin: CGFloat = 12
    private static let scale = 2

    private let options: GalleryOptions
    private let window: NSWindow
    /// The surface the card is drawn on. The card sits in the middle, so its orientation does not matter.
    private let canvas = NSView(frame: .zero)
    private let environment: ItemCellEnvironment

    init(options: GalleryOptions) {
        self.options = options
        window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: true)
        window.appearance = NSAppearance(named: options.appearance == .dark ? .darkAqua : .aqua)
        canvas.wantsLayer = true
        window.contentView = canvas
        // Roughly the panel's glass over a black desktop, so translucent parts read as in the app.
        canvas.layer?.backgroundColor = options.appearance == .dark
            ? CGColor(srgbRed: 0.125, green: 0.125, blue: 0.125, alpha: 1)
            : CGColor(srgbRed: 0.53, green: 0.53, blue: 0.53, alpha: 1)

        let heldFlags = options.modifierFlags
        environment = ItemCellEnvironment(
            imageDecoder: ImageDecoder(),
            now: { SampleCard.now },
            currentModifierFlags: { heldFlags }
        )
    }

    /// Lays the card out so that its images start decoding; `render` then finds them in memory.
    func prepare(_ sample: SampleCard, sizeClass: SizeClass) {
        let cell = makeCell(for: sample, sizeClass: sizeClass)
        cell.removeFromSuperview()
    }

    /// The card as PNG data at 2x, on a canvas `margin` points larger on every side.
    func render(_ sample: SampleCard, sizeClass: SizeClass) -> Data? {
        let cell = makeCell(for: sample, sizeClass: sizeClass)
        defer { cell.removeFromSuperview() }

        // Views in a window that is not on screen only update their layers when asked to draw,
        // and AppKit builds some of them the first time they do.
        guard let scratch = canvas.bitmapImageRepForCachingDisplay(in: canvas.bounds) else { return nil }
        canvas.cacheDisplay(in: canvas.bounds, to: scratch)
        hideLabelRenderers(in: cell)
        guard let image = drawCanvas() else { return nil }
        return NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    /// Renders the canvas's layer tree into an sRGB bitmap.
    private func drawCanvas() -> CGImage? {
        let size = canvas.bounds.size
        guard let layer = canvas.layer,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                  data: nil,
                  width: Int(size.width) * Self.scale,
                  height: Int(size.height) * Self.scale,
                  bitsPerComponent: 8,
                  bytesPerRow: 0,
                  space: space,
                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              )
        else { return nil }
        context.scaleBy(x: CGFloat(Self.scale), y: CGFloat(Self.scale))
        layer.render(in: context)
        return context.makeImage()
    }

    /// A label draws its text through a private subview. When a layer tree is rendered into a
    /// bitmap, as here, both that subview and the text field itself draw the text, so
    /// translucent text comes out twice as opaque as on screen. Hiding the subview leaves one.
    private func hideLabelRenderers(in view: NSView) {
        for subview in view.subviews {
            if view is NSTextField, subview.className.contains("SimpleLabel") {
                subview.isHidden = true
            } else {
                hideLabelRenderers(in: subview)
            }
        }
    }

    private func makeCell(for sample: SampleCard, sizeClass: SizeClass) -> ItemCell {
        let side = sizeClass.cardSide
        let canvasSide = side + 2 * Self.margin
        window.setContentSize(NSSize(width: canvasSide, height: canvasSide))
        canvas.frame = CGRect(x: 0, y: 0, width: canvasSide, height: canvasSide)

        let cell = ItemCellFactory.cellClass(for: sample.model.type).init(frame: .zero)
        cell.frame = CGRect(x: Self.margin, y: Self.margin, width: side, height: side)
        canvas.addSubview(cell)
        cell.configure(with: sample.model, sizeClass: sizeClass, environment: environment)
        cell.isEmphasized = options.isEmphasized
        cell.isSelected = options.isSelected

        canvas.layoutSubtreeIfNeeded()
        canvas.displayIfNeeded()
        return cell
    }
}
