import AppKit
import PastoCore
import PastoCoreUI

/// Builds the "Pin" submenu of a card's context menu: one entry per pinboard, "Create
/// Pinboard…" and, in the history, "Unpin". There is no "move to": pinning an item that is on
/// another pinboard is what moves it.
enum PinMenu {
    /// How much of the selection is on a pinboard, which its entry shows as a check mark.
    nonisolated enum Membership: Equatable, Sendable {
        case all
        case some
        case none

        init(of pinboard: ListID, in selection: [Item]) {
            let count = selection.count { $0.listID == pinboard }
            self = count == 0 ? .none : count == selection.count ? .all : .some
        }

        var state: NSControl.StateValue {
            switch self {
            case .all: .on
            case .some: .mixed
            case .none: .off
            }
        }
    }

    /// What the entries do. All of them act on the selection the menu was built for.
    struct Actions {
        var pin: (_ pinboard: ListID) -> Void
        var createPinboardAndPin: () -> Void
        /// `nil` where "Unpin" is not offered.
        var unpin: (() -> Void)?
    }

    private static let dotSide: CGFloat = 12

    /// - Parameter pinboards: In the order of their tabs.
    static func make(selection: [Item], pinboards: [ClipList], actions: Actions) -> NSMenu {
        let menu = NSMenu()
        // Every pinboard can be chosen, the one on show and the ones the items are on included.
        menu.autoenablesItems = false

        for pinboard in pinboards {
            guard case .pinboard(let color) = pinboard.attributes else { continue }
            let id = pinboard.id
            let item = MenuItemHandler.item(title: TabBarItem(list: pinboard).name) { actions.pin(id) }
            item.image = dot(of: color)
            item.state = Membership(of: id, in: selection).state
            menu.addItem(item)
        }
        menu.addItem(.separator())
        menu.addItem(MenuItemHandler.item(title: ItemActionStrings.createPinboard, action: actions.createPinboardAndPin))
        if let unpin = actions.unpin {
            menu.addItem(MenuItemHandler.item(title: ItemActionStrings.unpin, action: unpin))
        }
        menu.showsItemImages()
        return menu
    }

    /// A pinboard's dot, the same image its tab and its cards show. Not a template: the colour
    /// is the point.
    private static func dot(of color: PinboardColor) -> NSImage {
        PinboardDot.image(color: color.displayColor, side: dotSide)
    }
}
