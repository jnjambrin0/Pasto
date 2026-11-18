import Foundation
import PastoCore
import PastoFoundation
import PastoInput
@testable import PastoStack

/// A stack model wired to stand-ins: a dictionary for the store, a recorder for pastes and a
/// hot key center that registers nothing with the system.
final class StackFixture {
    struct PasteCall: Equatable {
        var ids: [ItemID]
        var options: RestoreOptions
    }

    let config: ConfigStore
    let hotKeys = FakeHotKeys()
    /// What the store holds. Removing or changing an entry stands for a change in the store.
    var store: [ItemID: Item] = [:]
    private(set) var pastes: [PasteCall] = []
    /// What the paste collaborator answers.
    var pasteSucceeds = true
    private(set) var closeRequestCount = 0

    private let defaults = EphemeralDefaults()

    init() {
        config = ConfigStore(defaults: defaults.defaults)
    }

    func makeModel() -> StackModel {
        let model = StackModel(
            config: config,
            hotKeys: hotKeys,
            items: { [unowned self] ids in ids.compactMap { store[$0] } },
            paste: { [unowned self] ids, options in
                guard pasteSucceeds else { return false }
                pastes.append(PasteCall(ids: ids, options: options))
                return true
            }
        )
        model.onCloseRequest = { [unowned self] in closeRequestCount += 1 }
        return model
    }

    /// A text item that the store holds, identified by its text.
    @discardableResult
    func item(_ text: String) -> Item {
        let item = Item(
            id: ItemID(rawValue: text),
            type: .text,
            preview: .text(TextPreview(text: text, characterCount: text.count)),
            timestamp: Date(timeIntervalSinceReferenceDate: 0),
            createdAt: Date(timeIntervalSinceReferenceDate: 0)
        )
        store[item.id] = item
        return item
    }

    func items(_ texts: String...) -> [Item] {
        texts.map { item($0) }
    }
}

extension StackModel {
    /// The rows as the texts of their items, top to bottom.
    var texts: [String] {
        rows.map(\.item.id.rawValue)
    }
}

final class FakeHotKeys: StackHotKeyRegistering {
    private(set) var shortcuts: [String: Shortcut] = [:]
    private var actions: [String: @MainActor () -> Void] = [:]

    var callers: Set<String> { Set(shortcuts.keys) }

    func register(_ shortcut: Shortcut, caller: String, action: @escaping @MainActor () -> Void) {
        shortcuts[caller] = shortcut
        actions[caller] = action
    }

    func unregister(caller: String) {
        shortcuts[caller] = nil
        actions[caller] = nil
    }

    /// Stands for the user pressing the hot key.
    func press(_ hotKey: StackHotKey) {
        actions[hotKey.caller]?()
    }
}
