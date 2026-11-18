import AppKit
import PastoCore
import PastoCoreUI
import WebKit

/// The preview of a link: the page itself, loaded in a web view, with the address and a button
/// to open it in the browser underneath. Editing swaps the page for a text view holding the
/// address.
///
/// The page is loaded whenever the preview opens, whatever the link previews setting says:
/// that setting governs the metadata fetched at capture, not this. Like files, a page opens at
/// half the screen.
final class LinkContentView: NSView, ItemContentView, FooterProviding, PreferredSizeProviding, EditableContent,
    WKNavigationDelegate, NSTextViewDelegate {
    let footer = FooterView()
    var onCanCommitChange: ((Bool) -> Void)?
    var editingToolbar: NSView? { nil }

    private let environment: PreviewEnvironment
    private let itemID: ItemID
    private var url: URL
    /// The page's title as the stored preview has it; an edit carries it over.
    private var pageTitle: String?
    private var isEditing = false
    /// Set once the page failed and a blank one is being shown in its place.
    private var didFailLoading = false

    private let loader = NSProgressIndicator(frame: .zero)
    /// Shows a page that has started to arrive but has not finished within a moment.
    private var reveal: Task<Void, Never>?
    private lazy var webView = makeWebView()
    private lazy var addressView = makeAddressView()

    private static let blankPage = URL(string: "about:blank")

    init(item: Item, url: URL, environment: PreviewEnvironment) {
        self.environment = environment
        itemID = item.id
        self.url = url
        super.init(frame: .zero)
        loader.style = .spinning
        // A spinner that has stopped is otherwise left on screen, frozen over the page.
        loader.isDisplayedWhenStopped = false
        readPageTitle(of: item)
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("LinkContentView is created in code")
    }

    func update(with item: Item) {
        readPageTitle(of: item)
        guard case .link(let preview) = item.preview, preview.url != url else { return }
        url = preview.url
        if !isEditing {
            rebuild()
        }
    }

    private func readPageTitle(of item: Item) {
        if case .link(let preview) = item.preview {
            pageTitle = preview.title
        }
    }

    override func layout() {
        super.layout()
        let side = PreviewMetrics.loaderSide
        loader.frame = NSRect(x: (bounds.width - side) / 2, y: (bounds.height - side) / 2, width: side, height: side)
        subviews.filter { $0 !== loader }.forEach { $0.frame = bounds }
    }

    // MARK: - PreferredSizeProviding

    func preferredContentSize(screenSize: CGSize?) -> CGSize {
        PreviewSize.largeContentSize(screenSize: screenSize)
    }

    // MARK: - Modes

    /// Shows the page or the address editor, and the footer for the current address.
    private func rebuild() {
        subviews.forEach { $0.removeFromSuperview() }
        if isEditing {
            addSubview(addressView)
            addressView.string = url.absoluteString
            validate()
        } else {
            addSubview(webView)
            addSubview(loader)
            load(url)
        }
        needsLayout = true
        showFooter()
    }

    private func showFooter() {
        let button = PreviewButton(title: PreviewStrings.openIn(Self.browserName(for: url)))
        button.onClick = { [weak self] _ in self?.openInBrowser() }
        // A URL too long for one line goes on to the next ones.
        footer.setCaption(url.absoluteString, wraps: true, button: button)
    }

    /// The name of the application that opens the address, as its bundle gives it.
    private static func browserName(for url: URL) -> String {
        let name = NSWorkspace.shared.urlForApplication(toOpen: url)
            .flatMap { Bundle(url: $0) }?
            .object(forInfoDictionaryKey: "CFBundleName") as? String
        return name ?? PreviewStrings.browser
    }

    private func openInBrowser() {
        NSApp.deactivate()
        environment.handlers.open(url)
        environment.handlers.closePanel()
    }

    // MARK: - Page

    private func makeWebView() -> WKWebView {
        let webView = UnfocusableWebView(frame: .zero)
        webView.navigationDelegate = self
        webView.allowsLinkPreview = false
        return webView
    }

    private func load(_ address: URL) {
        didFailLoading = false
        reveal?.cancel()
        webView.isHidden = true
        loader.startAnimation(nil)
        webView.load(URLRequest(url: address, timeoutInterval: PreviewMetrics.pageTimeout))
    }

    /// The page is on show and the spinner gone.
    private func showPage() {
        reveal?.cancel()
        reveal = nil
        loader.stopAnimation(nil)
        webView.isHidden = false
    }

    /// The page has started to arrive. Most finish soon after; one that keeps loading (a slow
    /// image, a stream that never ends) is shown as far as it has got instead of leaving the
    /// spinner up until it is done.
    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        reveal?.cancel()
        reveal = Task { [weak self] in
            try? await Task.sleep(for: PreviewMetrics.pageRevealDelay)
            guard !Task.isCancelled else { return }
            self?.showPage()
        }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        showPage()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        pageDidFail()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        pageDidFail()
    }

    /// A page that cannot be loaded leaves a blank one: no message, no retry.
    private func pageDidFail() {
        guard !didFailLoading, let blankPage = Self.blankPage else {
            showPage()
            return
        }
        didFailLoading = true
        webView.load(URLRequest(url: blankPage, timeoutInterval: PreviewMetrics.pageTimeout))
    }

    // MARK: - Address editor

    private func makeAddressView() -> NSTextView {
        let textView = NSTextView(frame: .zero)
        textView.isEditable = true
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .preferredFont(forTextStyle: .body)
        textView.textColor = ItemPresentation.primaryTextColor
        textView.textContainerInset = PreviewMetrics.linkEditorInset
        textView.autoresizingMask = .width
        textView.delegate = self
        return textView
    }

    func textDidChange(_ notification: Notification) {
        validate()
    }

    /// Any address can be saved, changed or not.
    private func validate() {
        onCanCommitChange?(LinkInput.url(from: addressView.string) != nil)
    }

    // MARK: - EditableContent

    func beginEditing() {
        isEditing = true
        rebuild()
    }

    func cancelEditing() {
        isEditing = false
        rebuild()
    }

    func commitEditing() {
        isEditing = false
        if let edited = LinkInput.url(from: addressView.string) {
            environment.replaceContent(of: itemID, with: ItemContentComposer.link(edited, title: pageTitle ?? ""))
            url = edited
        }
        rebuild()
    }

    func focusEditor() {
        window?.makeFirstResponder(addressView)
    }
}

/// A web view that never takes keyboard focus: with the preview open, keys still belong to the
/// strip of cards.
private final class UnfocusableWebView: WKWebView {
    override var acceptsFirstResponder: Bool { false }
}
