import AppKit
import SwiftUI

/// The window of Pasto's permission prompts, onboarding and About: no visible title bar, the
/// content running under it, and draggable from anywhere.
@MainActor
public enum ChromelessWindow {
    /// The window is born with this content rect; its real size comes from its content.
    private static let initialContentRect = NSRect(x: 0, y: 0, width: 100, height: 100)

    public static func make(isClosable: Bool, animationBehavior: NSWindow.AnimationBehavior) -> NSWindow {
        var styleMask: NSWindow.StyleMask = [.titled, .fullSizeContentView]
        if isClosable {
            styleMask.insert(.closable)
        }
        let window = NSWindow(contentRect: initialContentRect, styleMask: styleMask, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.animationBehavior = animationBehavior
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.titleVisibility = .hidden
        return window
    }

    /// Makes `content` the whole of the window, at the size the content asks for. The content runs
    /// under the hidden title bar, so it is given no safe area: one would make the window taller
    /// than its content by the height of the title bar.
    public static func setContent(_ content: some View, of window: NSWindow) {
        let hostingView = NSHostingView(rootView: content)
        hostingView.safeAreaRegions = []
        window.contentView = hostingView
        window.setContentSize(hostingView.fittingSize)
    }
}
