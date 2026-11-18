import AppKit
import SwiftUI

/// The picture of a card in flight: the card as the list draws it, without its delete button,
/// under a deeper shadow and with room around it for that shadow.
enum StackDragImage {
    /// - Parameters:
    ///   - appearance: The panel's appearance, which the card is drawn in.
    ///   - scale: The backing scale of the screen the card is on.
    static func make(of content: StackCardContent, appearance: NSAppearance, scale: CGFloat) -> NSImage? {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let renderer = ImageRenderer(content:
            StackCard(content: content)
                .shadow(
                    color: .black.opacity(StackMetrics.Drag.liftedShadowOpacity),
                    radius: StackMetrics.Drag.liftedShadowRadius,
                    y: StackMetrics.Drag.liftedShadowOffset
                )
                .padding(StackMetrics.Drag.imagePadding)
                .environment(\.colorScheme, isDark ? .dark : .light)
        )
        renderer.scale = scale
        return renderer.nsImage
    }
}
