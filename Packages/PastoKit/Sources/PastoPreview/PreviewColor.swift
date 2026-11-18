import AppKit

/// The colours of the preview that the cards do not share with it (those come from
/// `ItemPresentation`).
enum PreviewColor {
    /// Black in a light appearance and white in a dark one, at `opacity`: the fills of the
    /// buttons and the faintest text.
    static func ink(_ opacity: CGFloat) -> NSColor {
        NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(opacity)
        }
    }
}
