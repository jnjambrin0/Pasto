import AppKit

/// The window that carries a row's card while the row is dragged, and back into its slot when
/// the drag is over. It floats just above the panel, can go anywhere on screen — the card leaves
/// the panel — and lets the pointer through.
final class StackLiftedCardWindow: NSWindow {
    /// - Parameters:
    ///   - image: The card, with its shadow and the room around it.
    ///   - origin: Where the image's bottom-left corner goes, in screen coordinates.
    init(image: NSImage, origin: NSPoint, level: NSWindow.Level) {
        super.init(
            contentRect: NSRect(origin: origin, size: image.size),
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        // The shadow is part of the image.
        hasShadow = false
        ignoresMouseEvents = true
        isReleasedWhenClosed = false
        self.level = level
        alphaValue = StackMetrics.Drag.liftedOpacity

        let imageView = NSImageView(image: image)
        imageView.imageScaling = .scaleAxesIndependently
        contentView = imageView
    }
}
