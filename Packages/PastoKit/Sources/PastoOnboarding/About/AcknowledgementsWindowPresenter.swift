import AppKit
import SwiftUI

/// Shows the Acknowledgements window: the licenses of the third-party software Pasto ships,
/// which those licenses require to travel with every copy. A plain, resizable document window;
/// there is one at most, built when first shown and thrown away when closed.
final class AcknowledgementsWindowPresenter: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show() {
        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: AboutMetrics.acknowledgementsSize),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.title = OnboardingStrings.acknowledgements
        window.contentMinSize = AboutMetrics.acknowledgementsMinimumSize
        window.contentView = NSHostingView(rootView: AcknowledgementsView(acknowledgements: .bundled()))
        window.delegate = self
        window.center()
        self.window = window
        return window
    }

    func windowWillClose(_ notification: Notification) {
        window?.contentView = nil
        window = nil
    }
}
