import PastoCore
import PastoUI

/// Maps a kind of item to the card that draws it.
public enum ItemCellFactory {
    public static func cellClass(for type: ItemType) -> ItemCell.Type {
        switch type {
        case .text: TextItemCell.self
        case .link: LinkItemCell.self
        case .image: ImageItemCell.self
        case .color: ColorItemCell.self
        case .files: FilesItemCell.self
        case .unknown: UnknownItemCell.self
        }
    }

    /// A recycled or new cell of the right class for `type`, not yet configured.
    ///
    /// `CollectionView.dequeueReusableCell(_:)` picks the class from its argument's static
    /// type, so each class is named here rather than passed as a value.
    public static func dequeueCell(for type: ItemType, from collectionView: CollectionView) -> ItemCell {
        switch type {
        case .text: collectionView.dequeueReusableCell(TextItemCell.self)
        case .link: collectionView.dequeueReusableCell(LinkItemCell.self)
        case .image: collectionView.dequeueReusableCell(ImageItemCell.self)
        case .color: collectionView.dequeueReusableCell(ColorItemCell.self)
        case .files: collectionView.dequeueReusableCell(FilesItemCell.self)
        case .unknown: collectionView.dequeueReusableCell(UnknownItemCell.self)
        }
    }
}
