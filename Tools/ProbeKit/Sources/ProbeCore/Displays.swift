import CoreGraphics
import Foundation

/// Resolves `--display` / `--screen` selectors: `main` or a zero-based index into the active displays.
public enum Displays {
    public static func resolve(_ selector: String) throws -> CGDirectDisplayID {
        if selector.lowercased() == "main" { return CGMainDisplayID() }
        let active = activeDisplays()
        guard let index = Int(selector), active.indices.contains(index) else {
            throw ProbeError.targetNotFound("no display '\(selector)' (use 'main' or an index below \(active.count))")
        }
        return active[index]
    }

    /// The display whose bounds contain a global point (top-left origin).
    public static func display(containing point: CGPoint) throws -> CGDirectDisplayID {
        guard let match = activeDisplays().first(where: { CGDisplayBounds($0).contains(point) }) else {
            throw ProbeError.targetNotFound("point \(point.x),\(point.y) is not on any display")
        }
        return match
    }

    /// Pixels per point of the display under a global point; the main display when none contains it.
    public static func scale(at point: CGPoint) -> Double {
        let display = (try? display(containing: point)) ?? CGMainDisplayID()
        guard let mode = CGDisplayCopyDisplayMode(display), mode.width > 0 else { return 1 }
        return Double(mode.pixelWidth) / Double(mode.width)
    }

    private static func activeDisplays() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else { return [] }
        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &displays, &count) == .success else { return [] }
        return Array(displays.prefix(Int(count)))
    }
}
