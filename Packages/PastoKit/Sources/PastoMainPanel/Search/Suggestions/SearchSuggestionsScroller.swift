import AppKit
import PastoUI

/// The body of the suggestions menu: the list on a glass backdrop, scrolling when it is taller
/// than the room below the search field. Where rows are hidden, a band with a chevron says so,
/// the rows fade out under it, and resting the pointer on it scrolls.
final class SearchSuggestionsScroller: NSView {
    let list = SearchSuggestionsListView(frame: .zero)

    private let backgroundView = BackgroundEffectView(cornerRadius: SearchMetrics.Suggestions.cornerRadius)
    private let scrollView = NSScrollView(frame: .zero)
    private let upIndicator = ScrollIndicatorView(symbol: SearchMetrics.Suggestions.scrollUpSymbol)
    private let downIndicator = ScrollIndicatorView(symbol: SearchMetrics.Suggestions.scrollDownSymbol)
    private var hoverScrollTimer: Timer?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        addSubview(backgroundView)

        scrollView.hasVerticalScroller = false
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = false
        scrollView.borderType = .noBorder
        scrollView.wantsLayer = true
        scrollView.usesPredominantAxisScrolling = true
        scrollView.documentView = list
        backgroundView.contentView.addSubview(scrollView)

        upIndicator.onHover = { [weak self] isInside in self?.setHoverScrolling(isInside ? -1 : nil) }
        downIndicator.onHover = { [weak self] isInside in self?.setHoverScrolling(isInside ? 1 : nil) }
        backgroundView.contentView.addSubview(upIndicator)
        backgroundView.contentView.addSubview(downIndicator)

        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(visibleRowsDidChange),
            name: NSView.boundsDidChangeNotification,
            object: scrollView.contentView
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SearchSuggestionsScroller is created in code")
    }

    /// As wide and as tall as the whole list.
    override var fittingSize: NSSize { list.fittingSize }

    /// Forgets the scroll position, for a menu that is about to show other rows.
    func scrollToTop() {
        scrollView.contentView.scroll(to: .zero)
    }

    override func layout() {
        super.layout()
        backgroundView.frame = bounds
        scrollView.frame = bounds
        list.frame = NSRect(x: 0, y: 0, width: bounds.width, height: list.fittingSize.height)

        let bandHeight = SearchMetrics.Suggestions.scrollIndicatorHeight
        upIndicator.frame = NSRect(x: 0, y: bounds.maxY - bandHeight, width: bounds.width, height: bandHeight)
        downIndicator.frame = NSRect(x: 0, y: 0, width: bounds.width, height: bandHeight)
        updateScrollIndicators()
    }

    @objc private func visibleRowsDidChange() {
        updateScrollIndicators()
    }

    // MARK: - Scroll indicators

    private var hiddenAbove: Bool { scrollView.documentVisibleRect.minY > 0 }
    private var hiddenBelow: Bool { scrollView.documentVisibleRect.maxY < list.frame.height }

    private func updateScrollIndicators() {
        upIndicator.isHidden = !hiddenAbove
        downIndicator.isHidden = !hiddenBelow
        updateFadeMask()
    }

    /// Rows fade out towards each end that hides more of them. The mask changes at once: being
    /// a layer of its own, it would otherwise fade every change in.
    private func updateFadeMask() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        guard hiddenAbove || hiddenBelow, bounds.height > 0 else {
            scrollView.layer?.mask = nil
            return
        }
        let mask = scrollView.layer?.mask as? CAGradientLayer ?? CAGradientLayer()
        let band = min(SearchMetrics.Suggestions.scrollIndicatorHeight / bounds.height, 0.5)
        let opaque = CGColor.black
        // The layer's y axis points up: the first stop is the bottom edge.
        mask.frame = scrollView.bounds
        mask.colors = [hiddenBelow ? CGColor.clear : opaque, opaque, opaque, hiddenAbove ? CGColor.clear : opaque]
        mask.locations = [0, NSNumber(value: band), NSNumber(value: 1 - band), 1]
        mask.startPoint = CGPoint(x: 0.5, y: 0)
        mask.endPoint = CGPoint(x: 0.5, y: 1)
        scrollView.layer?.mask = mask
    }

    /// Scrolls a row at a time, `direction` rows per tick, while the pointer rests on an
    /// indicator; nil stops.
    private func setHoverScrolling(_ direction: Int?) {
        hoverScrollTimer?.invalidate()
        hoverScrollTimer = nil
        guard let direction else { return }
        hoverScrollTimer = Timer.scheduledTimer(
            withTimeInterval: SearchMetrics.Suggestions.hoverScrollInterval,
            repeats: true
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.scrollRows(direction) }
        }
    }

    private func scrollRows(_ count: Int) {
        let visible = scrollView.documentVisibleRect
        let highest = max(list.frame.height - visible.height, 0)
        let y = min(max(visible.minY + CGFloat(count) * SearchMetrics.Suggestions.rowHeight, 0), highest)
        guard y != visible.minY else {
            setHoverScrolling(nil)
            return
        }
        scrollView.contentView.scroll(to: NSPoint(x: 0, y: y))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil { setHoverScrolling(nil) }
    }
}

/// A band at one end of the suggestions menu showing that there are more rows that way.
private final class ScrollIndicatorView: NSView {
    /// The pointer entered (true) or left (false) the band.
    var onHover: ((Bool) -> Void)?

    private let symbolView: SymbolView

    init(symbol: SymbolDescription) {
        symbolView = SymbolView(symbol: symbol)
        super.init(frame: .zero)
        symbolView.tintColor = .secondaryLabelColor
        addSubview(symbolView)
        addTrackingArea(NSTrackingArea(
            rect: .zero,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self
        ))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("ScrollIndicatorView is created in code")
    }

    override func layout() {
        super.layout()
        symbolView.frame = bounds
    }

    override func mouseEntered(with event: NSEvent) {
        onHover?(true)
    }

    override func mouseExited(with event: NSEvent) {
        onHover?(false)
    }

    override func viewDidHide() {
        super.viewDidHide()
        // A hidden view gets no exit event.
        onHover?(false)
    }
}
