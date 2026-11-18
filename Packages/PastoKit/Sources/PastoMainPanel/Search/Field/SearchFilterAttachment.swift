import AppKit

/// The attachment that stands for a filter in the search field's text: one character, drawn as
/// a token view.
///
/// AppKit declares attachments and their view providers without an actor, although a text view
/// only ever uses them on the main thread; hence the `nonisolated` types that assume it.
nonisolated final class SearchFilterAttachment: NSTextAttachment {
    /// Tells this token from any other in the field, including one for the same filter.
    let id = UUID()
    let title: String
    let icon: SearchFilterIcon
    /// The token was clicked; receives `id`.
    let onClick: @MainActor @Sendable (UUID) -> Void

    init(title: String, icon: SearchFilterIcon, onClick: @escaping @MainActor @Sendable (UUID) -> Void) {
        self.title = title
        self.icon = icon
        self.onClick = onClick
        super.init(data: nil, ofType: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("SearchFilterAttachment is created in code")
    }

    override func viewProvider(
        for parentView: NSView?,
        location: any NSTextLocation,
        textContainer: NSTextContainer?
    ) -> NSTextAttachmentViewProvider? {
        let provider = SearchFilterTokenViewProvider(
            textAttachment: self,
            parentView: parentView,
            textLayoutManager: textContainer?.textLayoutManager,
            location: location
        )
        provider.tracksTextAttachmentViewBounds = true
        return provider
    }
}

/// Builds the token view of a `SearchFilterAttachment` and tells the text system how much room
/// it takes on the line.
private nonisolated final class SearchFilterTokenViewProvider: NSTextAttachmentViewProvider {
    override func loadView() {
        guard let attachment = textAttachment as? SearchFilterAttachment else { return }
        let (id, title, icon, onClick) = (attachment.id, attachment.title, attachment.icon, attachment.onClick)
        view = MainActor.assumeIsolated {
            let token = SearchFilterTokenView(title: title, icon: icon)
            token.onClick = { onClick(id) }
            // The container adds the gap that separates the token from what follows it.
            let container = NSView(frame: NSRect(
                x: 0,
                y: 0,
                width: token.frame.width + SearchMetrics.Token.trailingGap,
                height: token.frame.height
            ))
            container.addSubview(token)
            return container
        }
    }

    override func attachmentBounds(
        for attributes: [NSAttributedString.Key: Any],
        location: any NSTextLocation,
        textContainer: NSTextContainer?,
        proposedLineFragment: CGRect,
        position: CGPoint
    ) -> CGRect {
        let view = view
        let size = MainActor.assumeIsolated { view?.frame.size ?? .zero }
        // Dropped below the baseline so that the token's label lines up with the typed text.
        return CGRect(
            x: 0,
            y: -SearchMetrics.Token.baselineDropFraction * size.height,
            width: size.width,
            height: size.height
        )
    }
}
