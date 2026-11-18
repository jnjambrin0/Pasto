import PastoUI

/// Shows the notice cards of a repository before the first item of the clipboard history, and
/// keeps them in step with it: a card that is added appears, one that is removed goes away.
///
/// Which cards exist, what their buttons do and what closing one means belong to whoever
/// creates the controller.
public final class NoticeCardsController {
    private weak var collectionView: ItemCollectionView?
    private var observation: Task<Void, Never>?

    /// - Parameters:
    ///   - closeButtonLabel: The name of a card's close button for assistive technologies.
    ///   - onAction: The button of a card was pressed.
    ///   - onClose: The close button of the card with this identifier was pressed.
    public init(
        repository: NoticeRepository,
        collectionView: ItemCollectionView,
        closeButtonLabel: String,
        onAction: @escaping (NoticeCard.Command) -> Void,
        onClose: @escaping (NoticeCard.ID) -> Void
    ) {
        let row = NoticeRowView(closeButtonLabel: closeButtonLabel)
        row.onAction = onAction
        row.onClose = onClose
        row.cards = repository.cards
        collectionView.noticeRow = row
        self.collectionView = collectionView

        observation = Task { [weak row] in
            for await cards in repository.values() {
                row?.cards = cards
            }
        }
    }

    isolated deinit {
        observation?.cancel()
        collectionView?.noticeRow = nil
    }
}
