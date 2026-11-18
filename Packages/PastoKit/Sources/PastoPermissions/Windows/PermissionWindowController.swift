import AppKit
import SwiftUI

/// Shows one permission window, modally or not, and tells when it is gone.
@MainActor
final class PermissionWindowController: NSObject, NSWindowDelegate {
    private let window: NSWindow
    private var onClose: (() -> Void)?

    /// - Parameters:
    ///   - title: Not shown — the title bar is hidden — but VoiceOver and Mission Control name
    ///     the window with it.
    ///   - content: Decides the size of the window.
    init(window: NSWindow, title: String, content: some View) {
        self.window = window
        super.init()
        window.title = title
        ChromelessWindow.setContent(content, of: window)
        window.delegate = self
    }

    var level: NSWindow.Level {
        get { window.level }
        set { window.level = newValue }
    }

    /// Blocks until the window closes, whoever closes it.
    func runModal() {
        window.center()
        NSApp.runModal(for: window)
    }

    func show(onClose: @escaping () -> Void) {
        self.onClose = onClose
        window.center()
        bringToFront()
    }

    func bringToFront() {
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    func close() {
        window.close()
    }

    /// Once access is granted the window closes by itself, so there is nothing left to cancel.
    func removeCloseButton() {
        window.styleMask.remove(.closable)
    }

    func windowWillClose(_ notification: Notification) {
        if NSApp.modalWindow === window {
            NSApp.stopModal()
        }
        onClose?()
        onClose = nil
    }
}
