import AppKit
import PastoPermissions
import SwiftUI

/// Shows the About window. There is one at most; it is built when first shown and thrown away
/// when closed. It also owns the Acknowledgements window its button opens.
public final class AboutWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private let acknowledgements = AcknowledgementsWindowPresenter()

    override public init() {}

    /// Opens the window, or brings the open one forward, and makes Pasto the active application.
    public func show() {
        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the third-party licenses: from the About window's button, or from a menu entry.
    public func showAcknowledgements() {
        acknowledgements.show()
    }

    private func makeWindow() -> NSWindow {
        let window = ChromelessWindow.make(isClosable: true, animationBehavior: .alertPanel)
        // Not shown (the title bar is hidden), but VoiceOver and Mission Control name the window.
        window.title = OnboardingStrings.aboutWindowTitle
        ChromelessWindow.setContent(AboutView { [weak self] in self?.showAcknowledgements() }, of: window)
        window.delegate = self
        window.center()
        self.window = window
        return window
    }

    public func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}
