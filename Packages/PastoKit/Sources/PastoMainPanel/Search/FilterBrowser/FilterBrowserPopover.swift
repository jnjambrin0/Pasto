import AppKit
import PastoUI
import SwiftUI

/// The popover that holds the filter browser. It opens animated and closes at once, and while it
/// is open the keyboard moves a highlight through the filters.
final class FilterBrowserPopover: NSPopover, NSPopoverDelegate {
    /// The popover is about to close, whatever closed it.
    var onWillClose: (() -> Void)?

    /// True from the moment the popover starts to show until it starts to close.
    private(set) var isDisplayed = false

    private var model: FilterBrowserModel?
    private var keyMonitor: Any?

    override init() {
        super.init()
        behavior = .transient
        delegate = self
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("FilterBrowserPopover is created in code")
    }

    /// Shows the browser for `model` hanging below `anchor`.
    func show(_ model: FilterBrowserModel, below anchor: NSView) {
        self.model = model
        let controller = NSHostingController(rootView: FilterBrowserView(model: model))
        controller.view.wantsLayer = true
        controller.view.layer?.backgroundColor = .clear
        contentViewController = controller

        show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .minY)
        // Only the opening is animated; closing turns the animation back on for the next one.
        animates = false
    }

    // MARK: - Keys

    /// - Returns: Whether the key was the browser's. Return and Tab always are; anything it
    ///   has no use for goes on to the first responder.
    private func handleKeyDown(_ event: NSEvent) -> Bool {
        guard let model else { return false }
        let modifiers = event.modifierFlags
        switch event.keyCode {
        case KeyCode.returnKey:
            model.activateHighlighted(keepsOpen: modifiers.contains(.command))
        case KeyCode.tab:
            model.moveHighlight(modifiers.isDisjoint(with: [.shift, .option]) ? .right : .left)
        case KeyCode.rightArrow:
            model.moveHighlight(.right)
        case KeyCode.leftArrow:
            model.moveHighlight(.left)
        case KeyCode.upArrow:
            model.moveHighlight(.up)
        case KeyCode.downArrow:
            model.moveHighlight(.down)
        case KeyCode.escape:
            model.close()
        default:
            return false
        }
        return true
    }

    // MARK: - NSPopoverDelegate

    func popoverWillShow(_ notification: Notification) {
        isDisplayed = true
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handleKeyDown(event) == true ? nil : event
        }
    }

    func popoverWillClose(_ notification: Notification) {
        isDisplayed = false
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
        model = nil
        contentViewController = nil
        animates = true
        onWillClose?()
    }
}
