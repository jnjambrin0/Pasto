import AppKit
import SwiftUI

/// Shows a shortcut and, over its trailing end, the button that clears it. A click on the field
/// asks its owner to start or stop recording; the listening itself is `ShortcutRecorder`'s, in
/// `PastoInput`. The field looks the same while it records: only its text tells.
public struct ShortcutRecorderField: View {
    private let title: String
    private let text: String
    private let hasShortcut: Bool
    private let isRecording: Bool
    private let clearLabel: String
    private let onToggleRecording: () -> Void
    private let onClear: () -> Void

    /// - Parameters:
    ///   - title: What the shortcut does, for assistive technologies.
    ///   - text: The shortcut as written for the user, or a placeholder.
    ///   - clearLabel: The name of the clear button.
    public init(
        title: String,
        text: String,
        hasShortcut: Bool,
        isRecording: Bool,
        clearLabel: String,
        onToggleRecording: @escaping () -> Void,
        onClear: @escaping () -> Void
    ) {
        self.title = title
        self.text = text
        self.hasShortcut = hasShortcut
        self.isRecording = isRecording
        self.clearLabel = clearLabel
        self.onToggleRecording = onToggleRecording
        self.onClear = onClear
    }

    public var body: some View {
        Button(action: onToggleRecording) {
            Text(text)
                .font(.body)
                .lineLimit(1)
                // The field grows rather than cut its text short: a placeholder in another
                // language or a key with a long name still reads whole.
                .fixedSize()
                .foregroundStyle(showsShortcut ? .primary : .secondary)
                .padding(.leading, ShortcutRecorderMetrics.labelLeadingPadding)
                .padding(.trailing, ShortcutRecorderMetrics.labelTrailingPadding)
                .frame(minWidth: ShortcutRecorderMetrics.size.width)
                .frame(height: ShortcutRecorderMetrics.size.height)
                .background(Color(nsColor: .controlColor), in: shape)
                .overlay(shape.strokeBorder(.separator, lineWidth: ShortcutRecorderMetrics.borderWidth))
                .contentShape(shape)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityValue(text)
        .overlay(alignment: .trailing) {
            if showsShortcut {
                Button(action: onClear) {
                    Image(systemName: "xmark")
                        .font(.caption2)
                        .frame(width: ShortcutRecorderMetrics.clearButtonSide, height: ShortcutRecorderMetrics.clearButtonSide)
                        .contentShape(Rectangle())
                }
                .buttonStyle(ClearButtonStyle())
                .help(clearLabel)
                .accessibilityLabel(clearLabel)
            }
        }
    }

    private var showsShortcut: Bool {
        hasShortcut && !isRecording
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: ShortcutRecorderMetrics.cornerRadius, style: .continuous)
    }
}

/// The clear button: just the glyph, dimmed, and more so while pressed.
private struct ClearButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(
            configuration.isPressed ? ShortcutRecorderMetrics.clearButtonPressedOpacity : ShortcutRecorderMetrics.clearButtonOpacity
        )
    }
}
