import AppKit
import PastoCore

/// The preview and editing windows that are open, at most one per item.
final class PreviewWindowManager {
    private struct Entry {
        let itemID: ItemID
        let window: NSWindow
        let closeObserver: any NSObjectProtocol
    }

    private var entries: [Entry] = []

    /// How many windows are open.
    var count: Int { entries.count }

    func window(for itemID: ItemID) -> NSWindow? {
        entries.first { $0.itemID == itemID }?.window
    }

    /// Takes charge of a window until it closes. A window the item already had is closed first.
    func register(_ window: NSWindow, for itemID: ItemID) {
        self.window(for: itemID)?.close()
        let identifier = ObjectIdentifier(window)
        let observer = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.forget(identifier)
            }
        }
        entries.append(Entry(itemID: itemID, window: window, closeObserver: observer))
    }

    private func forget(_ window: ObjectIdentifier) {
        guard let index = entries.firstIndex(where: { ObjectIdentifier($0.window) == window }) else { return }
        let closed = entries.remove(at: index)
        NotificationCenter.default.removeObserver(closed.closeObserver)
        // AppKit is still using the window while it announces that it is closing; letting go
        // of it here, perhaps for the last time, has to wait until it is done.
        Task { withExtendedLifetime(closed.window) {} }
    }
}
