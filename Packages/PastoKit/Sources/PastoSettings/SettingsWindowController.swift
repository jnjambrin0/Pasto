import AppKit
import PastoCore
import PastoFoundation
import PastoInput

/// The Settings window.
///
/// There is one window at most. It is built when first shown and thrown away when closed, so it
/// always opens centred, on the General pane — or the one asked for — and with fresh state.
public final class SettingsWindowController {
    /// Called when the user erases or shortens the history here. Neither can be undone, and
    /// what was done to items before can no longer be undone either — the panel's undo stack
    /// is to be cleared.
    public var onIrreversibleItemChange: () -> Void {
        get { environment.didChangeItemsIrreversibly }
        set { environment.didChangeItemsIrreversibly = newValue }
    }

    /// Called once the user has erased the history here and the store has taken it.
    public var onEraseHistory: () -> Void {
        get { environment.didEraseHistory }
        set { environment.didEraseHistory = newValue }
    }

    /// Removes everything Pasto keeps on the Mac and quits: what Privacy › Remove All Data does
    /// once the user confirms it. Read when the window is built.
    public var onRemoveAllData: (() -> Void)? {
        get { environment.removeAllData }
        set { environment.removeAllData = newValue }
    }

    /// Whether this Mac has suggestions and what they still need, for the Intelligence pane and
    /// its badge in the sidebar. Until it is set, Settings shows no Intelligence pane. Read when
    /// the window is built.
    public var suggestions: SuggestionsAvailability {
        get { environment.suggestions }
        set { environment.suggestions = newValue }
    }

    private var environment: SettingsEnvironment
    private var window: NSWindow?
    private var closeObserver: (any NSObjectProtocol)?

    /// - Parameters:
    ///   - hotKeys: Paused while a shortcut is being recorded, so the recorder can see the
    ///     combinations Pasto itself holds.
    ///   - requestAccessibilityAccess: Presents the app's modal window for granting Accessibility
    ///     access. It is not called while another modal window is up.
    public init(
        config: ConfigStore,
        reader: StoreReader,
        writer: StoreWriter,
        hotKeys: HotKeyCenter,
        requestAccessibilityAccess: @escaping () -> Void
    ) {
        environment = SettingsEnvironment(
            config: config,
            reader: reader,
            writer: writer,
            hotKeys: hotKeys,
            requestAccessibilityAccess: requestAccessibilityAccess
        )
    }

    /// Opens the window, or brings the open one forward, and makes Pasto the active application.
    ///
    /// Since macOS 14 the "ignoring other apps" option has no effect: this is the same request
    /// as `activate()`.
    public func show() {
        let window = window ?? makeWindow()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Opens the window on `pane` (Help › Keyboard Shortcuts), or brings the open one forward
    /// and shows `pane` in it. A pane this Mac does not have leaves the window as it is.
    public func show(_ pane: SettingsPane) {
        show()
        (window?.contentViewController as? SettingsSplitViewController)?.select(pane)
    }

    private func makeWindow() -> NSWindow {
        let window = NSWindow(
            contentRect: SettingsMetrics.initialContentRect,
            styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.animationBehavior = .documentWindow
        // An empty toolbar under a transparent title bar is what gives the unified look, with the
        // sidebar running the full height of the window.
        window.toolbar = NSToolbar()
        window.titlebarAppearsTransparent = true
        // Not shown, but VoiceOver and Mission Control name the window with it.
        window.title = SettingsStrings.windowTitle
        window.titleVisibility = .hidden
        window.contentViewController = SettingsSplitViewController(environment: environment)
        // Panes are swapped in after the window is built: Tab has to find their controls too.
        window.autorecalculatesKeyViewLoop = true
        // The window is born small and takes its size from its content on the first layout;
        // centring before that would centre the small one.
        window.layoutIfNeeded()
        window.center()

        closeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.willCloseNotification, object: window, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.windowWillClose() }
        }
        self.window = window
        return window
    }

    private func windowWillClose() {
        if let closeObserver {
            NotificationCenter.default.removeObserver(closeObserver)
        }
        closeObserver = nil
        window?.contentViewController = nil
        window = nil
    }
}
