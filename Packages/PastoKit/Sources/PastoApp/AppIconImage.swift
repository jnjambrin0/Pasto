import AppKit
import os
import PastoFoundation
import UniformTypeIdentifiers

/// Pasto's icon as a finished image, for every alert and window that shows it.
///
/// An alert draws `NSImage(named: NSImage.applicationIconName)`, not `NSApp.applicationIconImage`:
/// an IconServices image that is only resolved when drawn, through LaunchServices' records of
/// the app's bundle identifier. With several copies of Pasto registered — development builds in
/// every worktree, archives, copies since deleted — the record LaunchServices picks need not be
/// the running copy (it prefers the highest version), and an alert of the development build
/// showed the generic application icon. Registering a finished image under that name before
/// anything reads it makes AppKit use it, in AppKit and SwiftUI alerts alike.
enum AppIconImage {
    /// The size the icon is drawn at once: enough for the largest place that shows it, the
    /// welcome screen's 160-point icon on a Retina display.
    private static let pixelSide = 512

    /// To be called before anything draws the icon, in `applicationWillFinishLaunching`. The
    /// system draws the icon in 50–90 ms the first time a process asks (measured on macOS 27.2),
    /// once per launch.
    static func install(bundle: Bundle = .main) {
        guard let icon = icon(of: bundle) else {
            Log.logger(.app).error("Could not draw Pasto's icon; alerts keep the system's")
            return
        }
        if !icon.setName(NSImage.applicationIconName) {
            Log.logger(.app).error("The application icon was drawn before Pasto could set it")
        }
        NSApp.applicationIconImage = icon
    }

    /// The icon of this copy as Finder and the Dock draw it, looked up by its path. If that
    /// comes back as the generic application icon, the icon compiled into the bundle instead.
    private static func icon(of bundle: Bundle) -> NSImage? {
        let system = NSWorkspace.shared.icon(forFile: bundle.bundlePath)
        if let drawn = bitmap(of: system, side: pixelSide), !looksAlike(system, NSWorkspace.shared.icon(for: .applicationBundle)) {
            let icon = NSImage(size: drawn.size)
            icon.addRepresentation(drawn)
            return icon
        }
        return bundle.image(forResource: "AppIcon")
    }

    /// `image` drawn now into a square bitmap of `side` pixels: an IconServices image drawn later
    /// can still be a placeholder.
    private static func bitmap(of image: NSImage, side: Int) -> NSBitmapImageRep? {
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: side * 4, bitsPerPixel: 32
        ), let context = NSGraphicsContext(bitmapImageRep: bitmap) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
        NSGraphicsContext.restoreGraphicsState()
        // Four pixels to the point, which keeps it sharp on a Retina display at the sizes shown.
        bitmap.size = NSSize(width: side / 4, height: side / 4)
        return bitmap
    }

    /// Whether two icons look the same at a small size: a real icon differs from the generic one
    /// almost everywhere.
    private static func looksAlike(_ first: NSImage, _ second: NSImage) -> Bool {
        let side = 32
        guard let firstBitmap = bitmap(of: first, side: side), let secondBitmap = bitmap(of: second, side: side) else {
            return false
        }
        return withExtendedLifetime((firstBitmap, secondBitmap)) {
            guard let one = firstBitmap.bitmapData, let other = secondBitmap.bitmapData else { return false }
            let byteCount = side * side * 4
            var differing = 0
            for index in 0..<byteCount where abs(Int(one[index]) - Int(other[index])) > 24 {
                differing += 1
            }
            return differing < byteCount / 20
        }
    }
}
