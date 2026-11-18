import AppKit
import PastoCoreUI
import SwiftUI

/// A row of the stack. A double click pastes it; a single click does nothing.
///
/// The card is drawn in the colour scheme its fill calls for, whatever the system's is: dark
/// text on a light fill, light text on a dark one.
struct StackCard: View {
    let content: StackCardContent
    var showsDeleteButton = false
    var onPaste: () -> Void = {}
    var onDelete: () -> Void = {}

    @Environment(\.colorScheme) private var colorScheme

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: StackMetrics.Card.cornerRadius, style: .continuous)
    }

    var body: some View {
        let backdrop = backdrop
        text
            .overlay(alignment: .trailing) {
                if let thumb = content.thumb {
                    StackThumbView(thumb: thumb)
                        .frame(width: StackMetrics.Card.thumbWidth)
                        .accessibilityHidden(true)
                }
            }
            .background(Color(nsColor: backdrop.color))
            .clipShape(shape)
            .shadow(color: .black.opacity(StackMetrics.Card.shadowOpacity), radius: StackMetrics.Card.shadowRadius)
            .contentShape(shape)
            .onTapGesture(count: 2, perform: onPaste)
            // What a double click does is VoiceOver's default action on the card.
            .accessibilityAction(.default, onPaste)
            .overlay(alignment: .topTrailing) {
                if showsDeleteButton {
                    deleteButton
                        .offset(x: StackMetrics.Card.deleteButtonOverhang, y: -StackMetrics.Card.deleteButtonOverhang)
                }
            }
            .environment(\.colorScheme, backdrop.isLight ? .light : .dark)
    }

    /// The card's fill and whether it is light, worked out in the panel's colour scheme.
    private var backdrop: (color: NSColor, isLight: Bool) {
        let isDark = colorScheme == .dark
        guard case .rich(let text) = content.text else { return (.textBackgroundColor, !isDark) }
        let backdrop = ItemPresentation.textBackdrop(of: text, isDark: isDark)
        return (backdrop.color, backdrop.isLight)
    }

    private var text: some View {
        textView
            .font(.body)
            .foregroundStyle(Color(nsColor: ItemPresentation.primaryTextColor))
            .padding(StackMetrics.Card.textPadding)
            .padding(.trailing, content.thumb == nil ? 0 : StackMetrics.Card.thumbWidth)
            .frame(width: StackMetrics.Card.width, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .mask { fade }
            .frame(maxHeight: StackMetrics.Card.maximumHeight, alignment: .top)
    }

    /// Formatting of its own wins over the card's font and colour.
    @ViewBuilder private var textView: some View {
        switch content.text {
        case .rich(let text):
            Text((try? AttributedString(text, including: \.appKit)) ?? AttributedString(text.string))
        case .plain(let string):
            Text(string)
        }
    }

    /// Text taller than a card may be is cut at the maximum height, its last lines fading out
    /// instead of ending in a hard edge.
    private var fade: some View {
        GeometryReader { proxy in
            let maximumHeight = StackMetrics.Card.maximumHeight
            if proxy.size.height > maximumHeight {
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: StackMetrics.Card.fadeStart),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: UnitPoint(x: 0.5, y: maximumHeight / proxy.size.height)
                )
            } else {
                Color.black
            }
        }
    }

    private var deleteButton: some View {
        Button(action: onDelete) {
            Image(systemName: "xmark")
                .font(.system(size: StackMetrics.Card.deleteButtonSymbolSize, weight: .bold))
                .foregroundStyle(.secondary)
                .frame(width: StackMetrics.Card.deleteButtonSide, height: StackMetrics.Card.deleteButtonSide)
                .glassEffect(.regular, in: Circle())
        }
        .buttonStyle(StackDeleteButtonStyle())
        .accessibilityLabel(StackStrings.delete)
    }
}

/// The delete button shrinks a little while it is pressed.
private struct StackDeleteButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? StackMetrics.Card.deleteButtonPressedScale : 1)
            .animation(StackMetrics.Motion.deleteButtonPress, value: configuration.isPressed)
    }
}
