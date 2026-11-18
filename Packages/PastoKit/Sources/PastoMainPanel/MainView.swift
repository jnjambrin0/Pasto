import AppKit
import PastoUI

/// Content of the clipboard panel: the glass backdrop holding the toolbar area and the item
/// strip, plus the resize handle along the top edge.
public final class MainView: LayerBackedView {
    public let toolbar = Toolbar()
    public let collectionView = ItemCollectionView()

    /// Text was typed with the keyboard focus on the item strip: whatever the input system
    /// delivers as text, a lone space included.
    var onTypeText: ((String) -> Void)?
    /// Escape reached the panel. Returns true when something took it, so the panel stays open.
    var onCancel: (() -> Bool)?
    /// Asked before anything else when Escape reaches the panel; true means it was taken.
    public var onEscape: (() -> Bool)?

    /// Fills the glass under the toolbar and the strip: the suggestions glow.
    var underlayView: NSView? {
        didSet {
            guard underlayView !== oldValue else { return }
            oldValue?.removeFromSuperview()
            if let underlayView {
                backgroundView.contentView.addSubview(underlayView, positioned: .below, relativeTo: nil)
            }
            needsLayout = true
        }
    }

    private let backgroundView = BackgroundEffectView(cornerRadius: MainPanelMetrics.backgroundCornerRadius)
    private let resizeHandle = ResizeHandle()

    public init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 0, height: MainPanelMetrics.defaultHeight))
        addSubview(backgroundView)
        backgroundView.contentView.addSubview(collectionView)
        backgroundView.contentView.addSubview(toolbar)
        addSubview(resizeHandle)

        resizeHandle.onLiveResize = { [weak self] in self?.mainWindow?.liveResize(toHeight: $0) }
        resizeHandle.onEndResize = { [weak self] in self?.mainWindow?.endResize() }
        resizeHandle.onReset = { [weak self] in self?.mainWindow?.resetHeight() }
    }

    private var mainWindow: MainWindow? { window as? MainWindow }

    override public func layout() {
        super.layout()
        let inset = MainPanelMetrics.backgroundInset
        // The glass touches the window's top edge and is inset on the sides and bottom.
        backgroundView.frame = NSRect(x: inset, y: inset, width: bounds.width - 2 * inset, height: bounds.height - inset)
        underlayView?.frame = NSRect(origin: .zero, size: backgroundView.frame.size)
        collectionView.frame = NSRect(
            x: 0,
            y: 0,
            width: backgroundView.frame.width,
            height: bounds.height - MainPanelMetrics.toolbarHeight - inset
        )
        toolbar.frame = NSRect(
            x: 0,
            y: collectionView.frame.maxY,
            width: backgroundView.frame.width,
            height: MainPanelMetrics.toolbarHeight
        )
        resizeHandle.frame = NSRect(
            x: 0,
            y: bounds.maxY - MainPanelMetrics.resizeHandleHeight,
            width: bounds.width,
            height: MainPanelMetrics.resizeHandleHeight
        )
    }

    // MARK: - First responder

    // Keyboard focus belongs to the item strip: the window starts there, and clicking anywhere
    // on the panel's chrome gives it back.

    override public func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.initialFirstResponder = collectionView
    }

    // The view itself stays out of the key view loop (it does not accept first responder), so
    // Tab never lands on it.

    override public func becomeFirstResponder() -> Bool {
        window?.makeFirstResponder(collectionView) ?? false
    }

    override public func mouseDown(with event: NSEvent) {
        super.mouseDown(with: event)
        window?.makeFirstResponder(collectionView)
    }

    // MARK: - Keyboard

    /// Keys nobody below consumed: give key equivalents a chance, then let the text system turn
    /// the event into an action (`cancelOperation:` for Escape, `insertText:` for typing).
    override public func keyDown(with event: NSEvent) {
        if super.performKeyEquivalent(with: event) { return }
        if event.keyCode == KeyCode.tab {
            super.keyDown(with: event)
        } else {
            interpretKeyEvents([event])
        }
    }

    /// Escape leaves a search before it closes the panel.
    override public func cancelOperation(_ sender: Any?) {
        if onEscape?() == true || onCancel?() == true { return }
        window?.performClose(sender)
    }

    /// Typing in the panel starts a search.
    override public func insertText(_ insertString: Any) {
        let text = (insertString as? NSAttributedString)?.string ?? insertString as? String
        if let text { onTypeText?(text) }
    }
}
