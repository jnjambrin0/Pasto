import CoreGraphics
import Foundation

/// Serialises a `Scene` as SVG 1.1. The output is deterministic: same scene, same bytes.
///
/// Only the features CoreSVG (Icon Composer, `actool`) and browsers agree on are used: paths,
/// user-space linear and radial gradients, clip paths, group opacity. Shadows become
/// `feDropShadow` filters and are left out entirely when `includeShadows` is false, which is how
/// the Icon Composer layers are written: the system draws their shadows itself.
struct SVGWriter {
    var includeShadows = true
    /// The part of the scene that becomes the document; defaults to the whole scene.
    var viewBox: CGRect?
    /// Output size in CSS pixels; defaults to the view box size.
    var size: CGSize?

    func document(_ scene: Scene) -> String {
        let box = viewBox ?? CGRect(x: 0, y: 0, width: scene.width, height: scene.height)
        let outputSize = size ?? box.size
        var defs = Definitions()
        var body: [String] = []

        for layer in scene.layers where !layer.items.isEmpty {
            var attributes = [("id", identifier(layer.name))]
            if let clip = layer.clip {
                attributes.append(("clip-path", "url(#\(defs.clipPath(clip)))"))
            }
            var inner: [String] = []
            for item in layer.items {
                inner.append(element(for: item, defs: &defs))
            }
            var group = inner
            if layer.opacity < 1 {
                group = ["<g opacity=\"\(number(layer.opacity))\">"] + indent(group) + ["</g>"]
            }
            if includeShadows, let shadow = layer.shadow {
                group = ["<g filter=\"url(#\(defs.filter(shadow)))\">"] + indent(group) + ["</g>"]
            }
            body.append("<g \(attributes.map { "\($0.0)=\"\($0.1)\"" }.joined(separator: " "))>")
            body.append(contentsOf: indent(group))
            body.append("</g>")
        }

        var lines = [
            "<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"\(number(outputSize.width))\" height=\"\(number(outputSize.height))\" "
                + "viewBox=\"\(number(box.minX)) \(number(box.minY)) \(number(box.width)) \(number(box.height))\">",
        ]
        if !defs.lines.isEmpty {
            lines.append("  <defs>")
            lines.append(contentsOf: indent(defs.lines, by: 4))
            lines.append("  </defs>")
        }
        lines.append(contentsOf: indent(body))
        lines.append("</svg>")
        return lines.joined(separator: "\n") + "\n"
    }

    private func element(for item: Item, defs: inout Definitions) -> String {
        var attributes = [("d", pathData(item.path))]
        let paint = defs.paint(item.paint)
        if let width = item.strokeWidth {
            attributes.append(("fill", "none"))
            attributes.append(("stroke", paint.value))
            if let opacity = paint.opacity { attributes.append(("stroke-opacity", opacity)) }
            attributes.append(("stroke-width", number(width)))
            attributes.append(("stroke-linecap", "round"))
            attributes.append(("stroke-linejoin", "round"))
        } else {
            attributes.append(("fill", paint.value))
            if let opacity = paint.opacity { attributes.append(("fill-opacity", opacity)) }
            if item.fillRule == .evenOdd { attributes.append(("fill-rule", "evenodd")) }
        }
        if let clip = item.clip {
            attributes.append(("clip-path", "url(#\(defs.clipPath(clip)))"))
        }
        return "<path " + attributes.map { "\($0.0)=\"\($0.1)\"" }.joined(separator: " ") + "/>"
    }

    /// Collects gradients, clip paths and filters, numbering them in order of first use.
    private struct Definitions {
        var lines: [String] = []
        private var count = 0

        private mutating func nextID(_ prefix: String) -> String {
            count += 1
            return "\(prefix)\(count)"
        }

        mutating func paint(_ paint: Paint) -> (value: String, opacity: String?) {
            switch paint {
            case let .solid(color):
                return (color.hex, color.alpha < 1 ? number(color.alpha) : nil)
            case let .linear(from, to, stops):
                let id = nextID("g")
                lines.append("<linearGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" x1=\"\(number(from.x))\" y1=\"\(number(from.y))\" "
                    + "x2=\"\(number(to.x))\" y2=\"\(number(to.y))\">")
                lines.append(contentsOf: stops.map(stopLine))
                lines.append("</linearGradient>")
                return ("url(#\(id))", nil)
            case let .radial(center, radius, stops):
                let id = nextID("g")
                lines.append("<radialGradient id=\"\(id)\" gradientUnits=\"userSpaceOnUse\" cx=\"\(number(center.x))\" "
                    + "cy=\"\(number(center.y))\" r=\"\(number(radius))\">")
                lines.append(contentsOf: stops.map(stopLine))
                lines.append("</radialGradient>")
                return ("url(#\(id))", nil)
            }
        }

        private func stopLine(_ stop: GradientStop) -> String {
            var line = "  <stop offset=\"\(number(stop.offset))\" stop-color=\"\(stop.color.hex)\""
            if stop.color.alpha < 1 { line += " stop-opacity=\"\(number(stop.color.alpha))\"" }
            return line + "/>"
        }

        mutating func clipPath(_ path: CGPath) -> String {
            let id = nextID("c")
            lines.append("<clipPath id=\"\(id)\"><path d=\"\(pathData(path))\"/></clipPath>")
            return id
        }

        mutating func filter(_ shadow: Shadow) -> String {
            let id = nextID("s")
            lines.append("<filter id=\"\(id)\" x=\"-25%\" y=\"-25%\" width=\"150%\" height=\"150%\" color-interpolation-filters=\"sRGB\">")
            lines.append("  <feDropShadow dx=\"0\" dy=\"\(number(shadow.dy))\" stdDeviation=\"\(number(shadow.blur / 2))\" "
                + "flood-color=\"\(shadow.color.hex)\" flood-opacity=\"\(number(shadow.color.alpha))\"/>")
            lines.append("</filter>")
            return id
        }
    }
}

/// SVG path data for a CGPath, two decimals at most.
func pathData(_ path: CGPath) -> String {
    var parts: [String] = []
    func point(_ p: CGPoint) -> String { "\(number(p.x)) \(number(p.y))" }
    path.applyWithBlock { element in
        let e = element.pointee
        switch e.type {
        case .moveToPoint:
            parts.append("M" + point(e.points[0]))
        case .addLineToPoint:
            parts.append("L" + point(e.points[0]))
        case .addQuadCurveToPoint:
            parts.append("Q" + point(e.points[0]) + " " + point(e.points[1]))
        case .addCurveToPoint:
            parts.append("C" + point(e.points[0]) + " " + point(e.points[1]) + " " + point(e.points[2]))
        case .closeSubpath:
            parts.append("Z")
        @unknown default:
            break
        }
    }
    return parts.joined()
}

/// Shortest decimal with at most `digits` decimals, no trailing zeros, never "-0".
func number(_ value: CGFloat, digits: Int = 2) -> String {
    let factor = pow(10, Double(digits))
    var rounded = (Double(value) * factor).rounded() / factor
    if rounded == 0 { rounded = 0 }
    var text = String(format: "%.\(digits)f", rounded)
    if text.contains(".") {
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
    }
    return text
}

private func identifier(_ name: String) -> String {
    name.map { $0.isLetter || $0.isNumber || $0 == "-" ? String($0) : "-" }.joined()
}

private func indent(_ lines: [String], by spaces: Int = 2) -> [String] {
    let pad = String(repeating: " ", count: spaces)
    return lines.map { pad + $0 }
}
