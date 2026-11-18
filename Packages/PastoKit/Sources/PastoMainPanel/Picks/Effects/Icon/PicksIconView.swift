import AppKit
import QuartzCore
import simd

/// The animated suggestions icon: a warm spark that breathes while it is on screen, and — in the
/// toolbar — quickens, grows and leans towards the pointer as it comes near, and shrinks a little
/// while its button is held down.
///
/// The motion comes from `PicksIconDynamics` with the numbers in `PicksIconMetrics`; the shape
/// comes from `PicksIconOutline`. The view is larger than the icon so that it can grow and lean
/// without being clipped; it lets every click through.
final class PicksIconView: FrameDrivenView {
    /// Written by the press callback of the button the icon sits in.
    var isPressed = false
    /// How close the pointer is, 0…1; the glow reads it.
    private(set) var excitement: Float = 0

    private let side: CGFloat
    private let respondsToPointer: Bool
    private let canvasFactor: Float
    private var state = PicksIconState()

    /// Clipped to the outline, it holds the fill and the sheen.
    private let bodyLayer = CALayer()
    private let outlineLayer = CAShapeLayer()
    private let fillLayer = CAGradientLayer()
    private let sheenLayer = CAGradientLayer()

    /// - Parameters:
    ///   - side: About the diameter of the icon at rest, in points.
    ///   - respondsToPointer: Whether the pointer excites it.
    init(side: CGFloat, respondsToPointer: Bool) {
        self.side = side
        self.respondsToPointer = respondsToPointer
        canvasFactor = PicksIconDynamics.canvasFactor(reach: PicksIconOutline.reach, respondsToPointer: respondsToPointer)
        super.init(frame: .zero)

        fillLayer.type = .conic
        fillLayer.colors = PicksIconMetrics.fillColors
        sheenLayer.type = .radial
        sheenLayer.colors = [NSColor.white.withAlphaComponent(0.9).cgColor, NSColor.white.withAlphaComponent(0).cgColor]
        bodyLayer.addSublayer(fillLayer)
        bodyLayer.addSublayer(sheenLayer)
        bodyLayer.mask = outlineLayer
        layer?.addSublayer(bodyLayer)
        setFrameSize(intrinsicContentSize)
    }

    override var intrinsicContentSize: NSSize {
        let length = side * CGFloat(canvasFactor)
        return NSSize(width: length, height: length)
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func layout() {
        super.layout()
        updateLayers()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateContentsScale()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateContentsScale()
    }

    /// The outline clips the fill, so it is rasterised at the screen's resolution.
    private func updateContentsScale() {
        let scale = window?.backingScaleFactor ?? 2
        for layer in [bodyLayer, outlineLayer, fillLayer, sheenLayer] {
            layer.contentsScale = scale
        }
    }

    override func render(now: CFTimeInterval, dt: Float, motion: Float) {
        state.advance(
            pointer: respondsToPointer ? pointerLocation : nil,
            size: bounds.size,
            isPressed: isPressed,
            unit: unit,
            dt: dt,
            motion: motion
        )
        excitement = state.excitement
        updateLayers()
    }

    private var unit: Float { PicksIconDynamics.unit(canvasFactor: canvasFactor) }

    /// Polled every frame, inside the view or not.
    private var pointerLocation: CGPoint? {
        guard let window else { return nil }
        return convert(window.convertPoint(fromScreen: NSEvent.mouseLocation), from: nil)
    }

    // MARK: - Drawing

    private func updateLayers() {
        guard bounds.width > 0, bounds.height > 0 else { return }
        let uniforms = PicksIconDynamics.uniforms(
            state: state, unit: unit, modes: PicksIconOutline.harmonicCount, size: bounds.size
        )
        let outline = PicksIconOutline.shape(
            atPhase: state.phase,
            amplitude: PicksIconDynamics.amplitude(mood: state.mood),
            modeCount: uniforms.modeCount
        )
        // Normalised coordinates span half the view's side per unit, corrected for its aspect.
        let shift = CGPoint(
            x: CGFloat(uniforms.shiftX / uniforms.aspectX) * bounds.width / 2,
            y: CGFloat(uniforms.shiftY / uniforms.aspectY) * bounds.height / 2
        )
        let center = CGPoint(x: bounds.midX + shift.x, y: bounds.midY + shift.y)
        let radius = side / (2 * CGFloat(PicksIconMetrics.canvasNormalisation)) * CGFloat(uniforms.scale)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for layer in [bodyLayer, outlineLayer, fillLayer, sheenLayer] {
            layer.frame = bounds
        }
        outlineLayer.path = Self.path(of: outline, center: center, radius: radius)

        // The fill turns once per loop of the outline.
        let turn = Double(state.phase) * 2 * .pi
        let centerInUnits = CGPoint(x: center.x / bounds.width, y: center.y / bounds.height)
        fillLayer.startPoint = centerInUnits
        fillLayer.endPoint = CGPoint(x: centerInUnits.x + 0.5 * sin(turn), y: centerInUnits.y + 0.5 * cos(turn))

        let sheen = PicksIconMetrics.sheenCenter
        let sheenStart = CGPoint(
            x: (center.x + sheen.x * radius) / bounds.width,
            y: (center.y + sheen.y * radius) / bounds.height
        )
        sheenLayer.startPoint = sheenStart
        sheenLayer.endPoint = CGPoint(
            x: sheenStart.x + PicksIconMetrics.sheenRadius * radius / bounds.width,
            y: sheenStart.y + PicksIconMetrics.sheenRadius * radius / bounds.height
        )
        sheenLayer.opacity = min(max((uniforms.liveliness - 1) * PicksIconMetrics.sheenPerLiveliness, 0), 1)
        CATransaction.commit()
    }

    private static func path(of outline: FourierOutline, center: CGPoint, radius: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let segments = PicksIconMetrics.outlineSegments
        for index in 0..<segments {
            let angle = Float(index) / Float(segments) * 2 * .pi
            let distance = radius * CGFloat(1 + outline.offset(at: angle))
            let point = CGPoint(x: center.x + distance * CGFloat(cos(angle)), y: center.y + distance * CGFloat(sin(angle)))
            if index == 0 {
                path.move(to: point)
            } else {
                path.addLine(to: point)
            }
        }
        path.closeSubpath()
        return path
    }
}
