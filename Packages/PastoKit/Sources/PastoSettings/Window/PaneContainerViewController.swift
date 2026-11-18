import AppKit
import SwiftUI

/// The right-hand side of the window: a fixed header and, under it, the selected pane in a
/// scroll view.
///
/// The window has one fixed height for every pane (`SettingsMetrics.windowHeight`), not one
/// taken from any pane; a pane that needs more scrolls.
final class PaneContainerViewController: NSViewController {
    private let makePane: (SettingsPane) -> AnyView
    private let titleView = PaneTitleView()
    private let scrollView = NSScrollView()
    private var paneViews: [SettingsPane: NSView] = [:]
    private var shownPane: SettingsPane?

    /// - Parameter makePane: Builds a pane's view, the first time the pane is shown.
    init(makePane: @escaping (SettingsPane) -> AnyView) {
        self.makePane = makePane
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    override func loadView() {
        view = NSView()

        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        // The header already keeps the content clear of the title bar.
        scrollView.automaticallyAdjustsContentInsets = false

        for subview in [titleView, scrollView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(subview)
        }
        NSLayoutConstraint.activate([
            titleView.topAnchor.constraint(equalTo: view.topAnchor),
            titleView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            titleView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: titleView.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            view.heightAnchor.constraint(equalToConstant: SettingsMetrics.windowHeight),
        ])
        // General, unless a pane was asked for before the view existed.
        let pane = shownPane ?? .general
        shownPane = nil
        show(pane)
    }

    func show(_ pane: SettingsPane) {
        guard pane != shownPane else { return }
        let paneView = paneView(for: pane)
        scrollView.documentView = paneView
        let clipView = scrollView.contentView
        NSLayoutConstraint.activate([
            paneView.topAnchor.constraint(equalTo: clipView.topAnchor),
            paneView.leadingAnchor.constraint(equalTo: clipView.leadingAnchor),
            paneView.trailingAnchor.constraint(equalTo: clipView.trailingAnchor),
        ])
        titleView.title = pane.title
        shownPane = pane
    }

    private func paneView(for pane: SettingsPane) -> NSView {
        if let existing = paneViews[pane] { return existing }
        let hostingView = NSHostingView(rootView: makePane(pane))
        // The pane sits under the header, never under the title bar.
        hostingView.safeAreaRegions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        // A pane is exactly as tall as its content, also when that changes after the window was sized.
        hostingView.setContentHuggingPriority(.required, for: .vertical)
        hostingView.setContentCompressionResistancePriority(.required, for: .vertical)
        paneViews[pane] = hostingView
        return hostingView
    }
}
