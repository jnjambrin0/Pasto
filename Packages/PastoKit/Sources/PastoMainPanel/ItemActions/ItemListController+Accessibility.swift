import AppKit
import PastoCore
import PastoCoreUI
import PastoUI

// What VoiceOver can do with a card besides reading it: these run what the context menu runs.

extension ItemListController {
    /// Copy, Preview, Delete and Pin — Unpin too where the menu's pin submenu offers it —, acting
    /// on the selection as the menu's entries do; the strip has made the card part of it.
    public func collectionView(_ collectionView: CollectionView, accessibilityActionsForCellAt index: Int) -> [NSAccessibilityCustomAction] {
        guard let item = itemID(at: index).flatMap(reader.item) else { return [] }
        let id = item.id
        var actions = [
            action(ItemActionStrings.copy) { $0.perform(.copy, onItem: id) },
        ]
        if onPreview != nil {
            actions.append(action(ItemActionStrings.preview) { $0.perform(.preview, onItem: id) })
        }
        actions.append(action(ItemActionStrings.delete) { $0.perform(.delete, onItem: id) })
        actions.append(action(ItemActionStrings.pin) { $0.showPinMenu(over: id) })
        if shownCollection == .history, item.listID != nil {
            actions.append(action(ItemActionStrings.unpin) { controller in
                let ids = controller.selectedItemIDs
                controller.write { try $0.unpin(ids) }
            })
        }
        return actions
    }

    /// Pressing a card pastes it, as a double click does.
    public func collectionView(_ collectionView: CollectionView, accessibilityPressCellAt index: Int) -> Bool {
        guard itemID(at: index) != nil else { return false }
        requestPaste(ItemCollectionView.PasteRequest())
        return true
    }

    private func action(_ name: String, _ body: @escaping (ItemListController) -> Void) -> NSAccessibilityCustomAction {
        NSAccessibilityCustomAction(name: name) { [weak self] in
            guard let self else { return false }
            body(self)
            return true
        }
    }

    /// The context menu's pin submenu, over the card: the pinboards to pin the selection to.
    private func showPinMenu(over id: ItemID) {
        guard let index = index(of: id), let card = collectionView.cell(at: index) else { return }
        let menu = makePinMenu()
        menu.popUp(positioning: nil, at: NSPoint(x: card.bounds.midX, y: card.bounds.midY), in: card)
    }
}
