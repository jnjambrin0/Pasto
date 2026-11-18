import AppKit
import PastoCore
import Testing
@testable import PastoMainPanel

/// The items, order and separators of the tabs' menus. Titles are not compared: they are
/// localized.
@Suite struct TabMenuTests {
    private enum Entry: Equatable {
        case separator
        case command(TabMenuCommand)
        case rename(ListID)
        case customView
    }

    private final class Recorder: TabMenuActions {
        var commands: [TabMenuCommand] = []

        func perform(_ command: TabMenuCommand) {
            commands.append(command)
        }
    }

    private func entries(of menu: NSMenu) -> [Entry] {
        menu.items.map { item in
            if item.isSeparatorItem {
                .separator
            } else if let command = item.representedObject as? TabMenuCommand {
                .command(command)
            } else if let id = item.representedObject as? ListID {
                .rename(id)
            } else {
                .customView
            }
        }
    }

    @Test func historyTabMenu() {
        let tab = TabBarItem(id: .clipboard, name: "History", kind: .history)
        let controller = TabMenuController()
        controller.itemCount = { _ in 3 }
        #expect(entries(of: controller.makeTabMenu(for: tab)) == [.rename(.clipboard), .command(.eraseHistory)])
        // An empty history has nothing to erase.
        controller.itemCount = { _ in 0 }
        #expect(entries(of: controller.makeTabMenu(for: tab)) == [.rename(.clipboard)])
    }

    @Test func pinboardTabMenu() {
        let id = ListID(rawValue: "pinboard")
        let tab = TabBarItem(id: id, name: "Pinboard", kind: .pinboard(.green))
        let menu = TabMenuController().makeTabMenu(for: tab)
        #expect(entries(of: menu) == [
            .rename(id),
            .command(.deletePinboard(id)),
            .separator,
            .customView,
        ])
        #expect(menu.items.last?.view is PinboardColorMenuItemView)
    }

    @Test func itemsReportTheirCommandAndRenameGoesToTheTabBar() throws {
        let controller = TabMenuController()
        let recorder = Recorder()
        controller.actions = recorder
        var renamed: [ListID] = []
        controller.onRename = { renamed.append($0) }

        let id = ListID(rawValue: "pinboard")
        let menu = controller.makeTabMenu(for: TabBarItem(id: id, name: "Pinboard", kind: .pinboard(.blue)))
        for item in menu.items {
            guard let action = item.action else { continue }
            _ = try #require(item.target).perform(action, with: item)
        }
        #expect(recorder.commands == [.deletePinboard(id)])
        #expect(renamed == [id])
    }
}
