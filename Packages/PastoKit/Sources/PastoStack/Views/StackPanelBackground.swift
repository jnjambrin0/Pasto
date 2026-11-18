import SwiftUI

/// The surface of the panel: clear glass, a thin light line along the inside of its edge and a
/// shadow of its own, which falls in the window's transparent margin. With "Reduce transparency"
/// or "Increase contrast" the glass is the regular one, which keeps the secondary text on it
/// readable.
struct StackPanelBackground: View {
    @Environment(\.accessibilityReduceTransparency) private var reducesTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: StackMetrics.Panel.cornerRadius, style: .continuous)
        Color.clear
            .glassEffect(reducesTransparency || contrast == .increased ? .regular : .clear, in: shape)
            .overlay {
                shape.strokeBorder(
                    Color(.sRGB, white: StackMetrics.Panel.borderWhite, opacity: 1),
                    lineWidth: StackMetrics.Panel.borderWidth
                )
            }
            .shadow(
                color: .black.opacity(StackMetrics.Panel.shadowOpacity),
                radius: StackMetrics.Panel.shadowRadius,
                y: StackMetrics.Panel.shadowOffset
            )
    }
}
