import AppKit
import PastoSearch

/// The menu of filters offered for the word being typed: a borderless child window under the
/// search bar that never takes the keyboard focus, so typing goes on in the field while the
/// arrow keys move through the menu.
final class SearchSuggestionsMenu: NSWindow {
    /// The user chose a suggestion.
    var onAccept: ((SearchSuggestion) -> Void)?
    /// Escape was pressed with the menu open.
    var onEscape: (() -> Void)?
    /// The menu lost its reason to be open: a click elsewhere, or the panel is no longer key.
    var onLoseFocus: (() -> Void)?

    private let scroller = SearchSuggestionsScroller(frame: .zero)
    private var suggestions: [SearchSuggestion] = []
    private weak var anchorView: NSView?
    private var keyMonitor: Any?
    private var mouseMonitor: Any?

    init() {
        super.init(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        backgroundColor = .clear
        isOpaque = false
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        contentView = scroller

        scroller.list.onAccept = { [weak self] index in
            guard let self, suggestions.indices.contains(index) else { return }
            onAccept?(suggestions[index])
        }
        scroller.list.onEscape = { [weak self] in self?.onEscape?() }
    }

    var isShown: Bool { parent != nil }

    /// Shows `suggestions` under `anchorView`, with the first row's text just before `wordRect`
    /// — the word being completed, in `anchorView`'s coordinates. Does nothing if the anchor is
    /// not on a screen.
    func show(
        _ suggestions: [SearchSuggestion],
        icon: (SearchFilter) -> SearchFilterIcon,
        below anchorView: NSView,
        wordRect: NSRect
    ) {
        guard let anchorWindow = anchorView.window else { return }
        let anchorFrame = anchorWindow.convertToScreen(anchorView.convert(anchorView.bounds, to: nil))
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(anchorFrame.origin) }) else { return }

        self.suggestions = suggestions
        self.anchorView = anchorView
        scroller.list.setSuggestions(suggestions, icon: icon)
        // The list may have changed height inside a window that keeps its size.
        scroller.needsLayout = true
        scroller.scrollToTop()

        let metrics = SearchMetrics.Suggestions.self
        let fittingSize = scroller.fittingSize
        let width = max(fittingSize.width, metrics.minimumWidth)
        // No limit on rows other than the room down to the bottom of the screen.
        let height = min(fittingSize.height, anchorFrame.minY - screen.visibleFrame.minY - metrics.screenBottomMargin)
        let x = anchorFrame.minX + wordRect.minX - scroller.list.firstRowTextOffset - metrics.textLeadingOffset
        setFrame(NSRect(x: x, y: anchorFrame.minY - height, width: width, height: height), display: true)

        guard !isShown else { return }
        anchorWindow.addChildWindow(self, ordered: .above)
        startMonitoring(anchorWindow)
    }

    func hide() {
        guard isShown else { return }
        stopMonitoring()
        parent?.removeChildWindow(self)
        orderOut(nil)
    }

    // MARK: - Monitors

    private func startMonitoring(_ anchorWindow: NSWindow) {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.scroller.list.handleKeyDown(event) == true ? nil : event
        }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            // The click is not consumed: it also does whatever it was aimed at.
            if let self, isOutside(event) { onLoseFocus?() }
            return event
        }
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(anchorWindowDidResignKey),
            name: NSWindow.didResignKeyNotification,
            object: anchorWindow
        )
    }

    private func stopMonitoring() {
        for monitor in [keyMonitor, mouseMonitor].compactMap({ $0 }) {
            NSEvent.removeMonitor(monitor)
        }
        keyMonitor = nil
        mouseMonitor = nil
        NotificationCenter.default.removeObserver(self, name: NSWindow.didResignKeyNotification, object: nil)
    }

    /// Whether a click fell neither on the menu nor on the view it hangs from.
    private func isOutside(_ event: NSEvent) -> Bool {
        if event.window === self { return false }
        guard let anchorView, event.window === anchorView.window else { return true }
        return !anchorView.bounds.contains(anchorView.convert(event.locationInWindow, from: nil))
    }

    @objc private func anchorWindowDidResignKey() {
        onLoseFocus?()
    }
}
