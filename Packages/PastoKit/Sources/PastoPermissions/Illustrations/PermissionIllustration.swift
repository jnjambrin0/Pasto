import SwiftUI

/// The picture of a permission screen: the generated picture imported for it
/// (`Resources/Illustrations/onboarding-<kind>.png`), or its vector fallback.
///
/// The pictures are static and drawn at 8:5.
public struct PermissionIllustration: View {
    public enum Kind: String, CaseIterable, Sendable {
        /// Paste into other apps (Accessibility, "Device Control and Data Access" on macOS 27).
        case accessibility
        /// Read the clipboard ("Paste from Other Apps").
        case pasteboard
        /// Suggestions that read the window being pasted into (screen recording).
        case suggestions

        /// The imported picture's name.
        var imageName: String { "onboarding-\(rawValue)" }

        var vector: (IllustrationPainter) -> Void {
            switch self {
            case .accessibility: PermissionScenes.accessibility
            case .pasteboard: PermissionScenes.pasteboard
            case .suggestions: PermissionScenes.suggestions
            }
        }
    }

    /// The illustration's size when nothing else sizes it: 400 × 250 pt.
    public static let defaultSize = IllustrationMetrics.designSize
    /// 10 pt.
    public static let defaultCornerRadius = IllustrationMetrics.cornerRadius

    private let kind: Kind
    private let cornerRadius: CGFloat

    /// - Parameter cornerRadius: 0 for a picture that runs to the window's edges.
    public init(_ kind: Kind, cornerRadius: CGFloat = PermissionIllustration.defaultCornerRadius) {
        self.kind = kind
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        IllustrationFrame(imageName: kind.imageName, bundle: .module, cornerRadius: cornerRadius, vector: kind.vector)
    }
}
