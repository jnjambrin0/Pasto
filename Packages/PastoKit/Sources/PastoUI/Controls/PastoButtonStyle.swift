import AppKit
import SwiftUI

/// The app's own button look, shared by onboarding and the permission windows: a capsule as
/// wide as its label, filled blue for the main action and grey for the others. Pressing it
/// darkens the fill, shrinks it a little and fades the label, all at once; nothing changes under
/// the pointer or when disabled.
public struct PastoButtonStyle: ButtonStyle {
    public enum Kind: Sendable {
        /// The main action: white on blue, with a faint shadow of the accent colour.
        case filled
        /// A secondary action: the label colour on a translucent grey.
        case plain
    }

    private let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        let isPressed = configuration.isPressed
        configuration.label
            .font(.system(size: Metrics.labelPointSize, weight: .medium))
            .foregroundStyle(labelColor.opacity(isPressed ? pressedLabelOpacity : 1))
            .padding(.horizontal, Metrics.horizontalPadding)
            .frame(minHeight: Metrics.minimumHeight)
            .background(fill.brightness(isPressed ? Metrics.pressedBrightness : 0))
            .clipShape(Capsule(style: .continuous))
            .shadow(color: shadowColor, radius: Metrics.shadowRadius, x: 0, y: Metrics.shadowOffsetY)
            .scaleEffect(isPressed ? Metrics.pressedScale : 1)
            .contentShape(Capsule(style: .continuous))
    }

    private var labelColor: Color {
        switch kind {
        case .filled: .white
        case .plain: Color(nsColor: .labelColor)
        }
    }

    private var pressedLabelOpacity: Double {
        switch kind {
        case .filled: Metrics.filledPressedLabelOpacity
        case .plain: Metrics.plainPressedLabelOpacity
        }
    }

    private var fill: Color {
        switch kind {
        case .filled: Color(nsColor: .systemBlue)
        case .plain: Color(nsColor: Metrics.plainFill)
        }
    }

    private var shadowColor: Color {
        switch kind {
        case .filled: Color(nsColor: .controlAccentColor).opacity(Metrics.shadowOpacity)
        case .plain: .clear
        }
    }

    private enum Metrics {
        static let labelPointSize: CGFloat = 13
        static let horizontalPadding: CGFloat = 16
        static let minimumHeight: CGFloat = 36
        static let shadowOpacity = 0.25
        static let shadowRadius: CGFloat = 1
        static let shadowOffsetY: CGFloat = 0.75
        static let pressedBrightness = -0.1
        static let pressedScale: CGFloat = 0.99
        static let filledPressedLabelOpacity = 0.9
        static let plainPressedLabelOpacity = 0.5

        /// `#767680` at 12 % in light appearances and 24 % in dark ones.
        static let plainFill = NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            return NSColor(
                srgbRed: 0x76 / 255.0,
                green: 0x76 / 255.0,
                blue: 0x80 / 255.0,
                alpha: isDark ? 0.24 : 0.12
            )
        }
    }
}
