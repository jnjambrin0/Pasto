import PastoPermissions
import SwiftUI

/// The picture of an onboarding screen: the generated picture imported for it
/// (`Resources/Illustrations/onboarding-<kind>.png`, or the permission module's for the three
/// permission screens), or its vector fallback when the picture is missing.
///
/// 8:5, rounded (10 pt) and outlined; in dark mode the pictures, which only exist in light, are
/// dimmed a little inside their frame. On its own the view is 400 × 250 pt; given a width it keeps
/// 8:5. The pictures are static. Design, sizes and how to replace the pictures:
/// docs/design/onboarding-art.md.
public struct OnboardingIllustration: View {
    public enum Kind: String, CaseIterable, Sendable {
        /// What Pasto is: a fan of clip cards rising from the grass.
        case intro
        /// Paste into other apps: a card lands in a window; the Return key.
        case accessibility
        /// Read the clipboard: cards arrive into a clipboard with a check.
        case pasteboard
        /// Suggestions read the window being pasted into, on the Mac.
        case suggestions
        /// The activation shortcut and the panel it opens.
        case quickStart
    }

    /// The illustration's size when nothing else sizes it: 400 × 250 pt.
    public static let defaultSize = PermissionIllustration.defaultSize

    private let kind: Kind
    private let cornerRadius: CGFloat

    /// - Parameter cornerRadius: 10 pt by default; 0 for a picture that runs to the window's edges.
    public init(_ kind: Kind, cornerRadius: CGFloat = PermissionIllustration.defaultCornerRadius) {
        self.kind = kind
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        switch kind {
        case .intro:
            IllustrationFrame(imageName: "onboarding-intro", bundle: .module, cornerRadius: cornerRadius, vector: OnboardingScenes.intro)
        case .quickStart:
            IllustrationFrame(imageName: "onboarding-quickstart", bundle: .module, cornerRadius: cornerRadius,
                              vector: OnboardingScenes.quickStart)
        case .accessibility:
            PermissionIllustration(.accessibility, cornerRadius: cornerRadius)
        case .pasteboard:
            PermissionIllustration(.pasteboard, cornerRadius: cornerRadius)
        case .suggestions:
            PermissionIllustration(.suggestions, cornerRadius: cornerRadius)
        }
    }
}
