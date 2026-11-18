import AppKit
import SwiftUI

/// A flat button saying what a setting still needs: a red exclamation mark, the text and a
/// chevron, on a faint rounded fill, 6 pt under what it belongs to. General asks for
/// Accessibility access with it; Intelligence, for Apple Intelligence or screen recording access.
/// Both are built alike: a plain button, its label padded 6 pt on every side, on the 5 % ink in a
/// continuous rounded rectangle of radius 5, with the chevron in the 26 % ink.
struct SettingsWarningPill: View {
    let title: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Image(systemName: "exclamationmark.circle.fill")
                    .foregroundStyle(Color(nsColor: .systemRed))
                Text(title)
                Image(systemName: "chevron.right")
                    .foregroundStyle(Self.ink(SettingsMetrics.warningPillChevronOpacity))
            }
            .font(.subheadline)
            .padding(SettingsMetrics.warningPillPadding)
            .background(
                Self.ink(SettingsMetrics.warningPillFillOpacity),
                in: RoundedRectangle(cornerRadius: SettingsMetrics.warningPillCornerRadius, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.top, SettingsMetrics.warningPillTopSpacing)
    }

    /// Black in light appearances and white in dark ones, at `opacity`.
    private static func ink(_ opacity: CGFloat) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return (isDark ? NSColor.white : NSColor.black).withAlphaComponent(opacity)
        })
    }
}
