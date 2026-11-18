import CoreGraphics
import Foundation

/// Rounded rectangle with continuous ("squircle") corners, the outline macOS uses for app icons.
/// Plain circular arcs look pinched next to system shapes. The constants are the widely published
/// Bézier fit of that outline, as multiples of the corner radius.
func continuousRoundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let reach: CGFloat = 1.528665
    // The corner curve starts `reach * radius` before the corner; clamp so opposite corners never overlap.
    let r = min(radius, min(rect.width, rect.height) / (2 * reach))
    let path = CGMutablePath()

    // `back` points from the corner along the edge we arrive on, `ahead` along the edge we leave on.
    func corner(_ c: CGPoint, back: CGVector, ahead: CGVector) {
        func point(_ b: CGFloat, _ a: CGFloat) -> CGPoint {
            CGPoint(x: c.x + (back.dx * b + ahead.dx * a) * r, y: c.y + (back.dy * b + ahead.dy * a) * r)
        }
        path.addLine(to: point(reach, 0))
        path.addCurve(to: point(0.631494, 0.074911), control1: point(1.088493, 0), control2: point(0.868407, 0))
        path.addCurve(to: point(0.074911, 0.631494), control1: point(0.372824, 0.169060), control2: point(0.169060, 0.372824))
        path.addCurve(to: point(0, reach), control1: point(0, 0.868407), control2: point(0, 1.088493))
    }

    path.move(to: CGPoint(x: rect.minX + reach * r, y: rect.minY))
    corner(CGPoint(x: rect.maxX, y: rect.minY), back: CGVector(dx: -1, dy: 0), ahead: CGVector(dx: 0, dy: 1))
    corner(CGPoint(x: rect.maxX, y: rect.maxY), back: CGVector(dx: 0, dy: -1), ahead: CGVector(dx: -1, dy: 0))
    corner(CGPoint(x: rect.minX, y: rect.maxY), back: CGVector(dx: 1, dy: 0), ahead: CGVector(dx: 0, dy: -1))
    corner(CGPoint(x: rect.minX, y: rect.minY), back: CGVector(dx: 0, dy: 1), ahead: CGVector(dx: 1, dy: 0))
    path.closeSubpath()
    return path
}

/// Rounded rectangle with circular corners; used where a shape is a few pixels wide and the
/// continuous curve would eat the straight edges.
func roundedRect(_ rect: CGRect, radius: CGFloat) -> CGPath {
    let r = min(radius, min(rect.width, rect.height) / 2)
    return CGPath(roundedRect: rect, cornerWidth: r, cornerHeight: r, transform: nil)
}

/// One blade of grass, described by its base and where its tip ends up.
struct Blade: Sendable {
    /// Centre of the base.
    var x: CGFloat
    /// Width at the base.
    var width: CGFloat
    /// Vertical distance from the base to the tip.
    var height: CGFloat
    /// Horizontal offset of the tip from the base; this is what bends the blade.
    var lean: CGFloat
    /// How long the blade stays upright before it bends, as a fraction of its height (0.3–0.7).
    var stiffness: CGFloat = 0.5

    init(_ x: CGFloat, width: CGFloat, height: CGFloat, lean: CGFloat, stiffness: CGFloat = 0.5) {
        self.x = x
        self.width = width
        self.height = height
        self.lean = lean
        self.stiffness = stiffness
    }
}

/// The construction of a blade: a tapering ribbon around a curved spine.
///
/// The spine is a quadratic curve that leaves the ground vertically and then arcs towards the tip.
/// Each edge is the cubic equivalent of that curve pushed sideways by half the local width, which
/// tapers to nothing at the tip. The edge on the outside of the bend keeps more of its width for
/// longer, so a leaning blade reads as a soft sabre instead of a symmetric spike.
struct BladeOutline {
    var base: CGPoint
    var tip: CGPoint
    var leftBase: CGPoint
    var rightBase: CGPoint
    /// Cubic control points of the spine, base to tip.
    var spine: (CGPoint, CGPoint)
    /// Cubic control points of the left edge, base to tip.
    var left: (CGPoint, CGPoint)
    /// Cubic control points of the right edge, base to tip.
    var right: (CGPoint, CGPoint)

    init(_ blade: Blade, baseY: CGFloat) {
        base = CGPoint(x: blade.x, y: baseY)
        tip = CGPoint(x: blade.x + blade.lean, y: baseY - blade.height)
        let knee = CGPoint(x: blade.x, y: baseY - blade.height * blade.stiffness)
        // Cubic control points of the quadratic spine (base, knee, tip).
        let c1 = CGPoint(x: base.x + (knee.x - base.x) * 2 / 3, y: base.y + (knee.y - base.y) * 2 / 3)
        let c2 = CGPoint(x: tip.x + (knee.x - tip.x) * 2 / 3, y: tip.y + (knee.y - tip.y) * 2 / 3)
        spine = (c1, c2)

        // Unit normal to the left of the direction a → b. In y-down space the left-hand normal of
        // (dx, dy) is (dy, -dx): (-1, 0) for a blade pointing straight up.
        func leftNormal(from a: CGPoint, to b: CGPoint) -> CGVector {
            let dx = b.x - a.x, dy = b.y - a.y
            let length = max(hypot(dx, dy), 0.0001)
            return CGVector(dx: dy / length, dy: -dx / length)
        }
        let n1 = leftNormal(from: base, to: knee)
        let n2 = leftNormal(from: knee, to: tip)
        let half = blade.width / 2
        // Leaning right puts the left edge on the outside of the bend.
        let outerIsLeft = blade.lean >= 0
        let outer: (CGFloat, CGFloat) = (0.95, 0.45)
        let inner: (CGFloat, CGFloat) = (0.80, 0.20)
        let l = outerIsLeft ? outer : inner
        let r = outerIsLeft ? inner : outer
        func offset(_ p: CGPoint, _ n: CGVector, _ d: CGFloat) -> CGPoint {
            CGPoint(x: p.x + n.dx * d, y: p.y + n.dy * d)
        }
        leftBase = CGPoint(x: base.x - half, y: base.y)
        rightBase = CGPoint(x: base.x + half, y: base.y)
        left = (offset(c1, n1, half * l.0), offset(c2, n2, half * l.1))
        right = (offset(c1, n1, -half * r.0), offset(c2, n2, -half * r.1))
    }

    var path: CGPath {
        let path = CGMutablePath()
        path.move(to: leftBase)
        path.addCurve(to: tip, control1: left.0, control2: left.1)
        path.addCurve(to: rightBase, control1: right.1, control2: right.0)
        path.closeSubpath()
        return path
    }

    /// The half of the blade between its spine and one edge; lit differently, it reads as a fold.
    func half(left isLeft: Bool) -> CGPath {
        let path = CGMutablePath()
        if isLeft {
            path.move(to: leftBase)
            path.addCurve(to: tip, control1: left.0, control2: left.1)
            path.addCurve(to: base, control1: spine.1, control2: spine.0)
        } else {
            path.move(to: base)
            path.addCurve(to: tip, control1: spine.0, control2: spine.1)
            path.addCurve(to: rightBase, control1: right.1, control2: right.0)
        }
        path.closeSubpath()
        return path
    }
}

func bladePath(_ blade: Blade, baseY: CGFloat) -> CGPath {
    BladeOutline(blade, baseY: baseY).path
}

/// An arrow along a gentle arc from `start` to `end`: the shaft and an open chevron head, both
/// meant to be stroked with round caps.
func arrowPaths(from start: CGPoint, to end: CGPoint, sag: CGFloat, headLength: CGFloat) -> (shaft: CGPath, head: CGPath) {
    let mid = CGPoint(x: (start.x + end.x) / 2, y: (start.y + end.y) / 2 + sag)
    let shaft = CGMutablePath()
    shaft.move(to: start)
    shaft.addQuadCurve(to: end, control: mid)

    // Head direction: tangent of the quadratic at its end.
    let dx = end.x - mid.x, dy = end.y - mid.y
    let angle = atan2(dy, dx)
    let spread: CGFloat = .pi * 0.23
    let head = CGMutablePath()
    head.move(to: CGPoint(x: end.x - cos(angle - spread) * headLength, y: end.y - sin(angle - spread) * headLength))
    head.addLine(to: end)
    head.addLine(to: CGPoint(x: end.x - cos(angle + spread) * headLength, y: end.y - sin(angle + spread) * headLength))
    return (shaft, head)
}
