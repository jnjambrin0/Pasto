import AppKit
import PastoCore
import PastoFoundation
import PastoInput

/// The way into the Paste Stack for the rest of the app: the global shortcut and the main panel.
///
/// There is at most one stack. It exists while its panel is open and keeps nothing afterwards:
/// every opening starts empty.
public final class StackWindowManager {
    private let dependencies: StackDependencies
    private let config: ConfigStore
    private let hotKeys: HotKeyCenter
    private var controller: StackWindowController?
    private var observations: [Task<Void, Never>] = []

    public init(dependencies: StackDependencies, config: ConfigStore, hotKeys: HotKeyCenter) {
        self.dependencies = dependencies
        self.config = config
        self.hotKeys = hotKeys

        // Listening from the start, rather than from the moment a stack opens, leaves no gap in
        // which the copy that opened it could be missed.
        observations = [
            Task { [weak self] in
                for await event in await dependencies.captureEvents() {
                    guard case .captured(let capture) = event else { continue }
                    self?.controller?.model.didCapture(capture.itemID)
                }
            },
            Task { [weak self] in
                for await _ in dependencies.storeChanges() {
                    self?.controller?.model.reconcileWithStore()
                }
            },
        ]
    }

    isolated deinit {
        observations.forEach { $0.cancel() }
    }

    /// Whether the stack's panel is on screen. The copy sound depends on it.
    public var isVisible: Bool { controller?.window?.isVisible ?? false }

    /// The items of the rows, top to bottom; empty when there is no stack.
    public var itemIDs: [ItemID] {
        controller?.model.rows.map(\.item.id) ?? []
    }

    /// What the "Activate Paste Stack" shortcut does: copies the selection of the frontmost
    /// application and makes sure a stack is open to receive it. It is not a toggle — with a
    /// stack already open it only copies, and the copy becomes a row like any other.
    public func activate() {
        guard dependencies.copy(), controller == nil else { return }
        show(with: [])
    }

    /// Adds rows for the given items, opening a stack if there is none.
    public func add(_ ids: [ItemID]) {
        let items = dependencies.items(ids)
        if let controller {
            controller.model.add(items)
        } else {
            show(with: items)
        }
    }

    /// Removes the rows of the given items. Without a stack it does nothing.
    public func remove(_ ids: [ItemID]) {
        controller?.model.remove(itemIDs: ids)
    }

    private func show(with items: [Item]) {
        let model = StackModel(config: config, hotKeys: hotKeys, items: dependencies.items, paste: dependencies.paste)
        let controller = StackWindowController(model: model, config: config, dependencies: dependencies)
        model.add(items)
        // The first stack says what it is for; once it has been on screen, no other does.
        model.showsFirstUseHint = !config.value(for: .hasSeenPasteStackHint)
        self.controller = controller
        controller.onClose = { [weak self, config, model] in
            if model.showsFirstUseHint {
                config.set(true, for: .hasSeenPasteStackHint)
            }
            self?.controller = nil
        }
        // The panel can never be key, so this only brings it to the front.
        controller.showWindow(nil)
    }
}

private extension ConfigKey where Value == Bool {
    /// The first-use line of the stack has been shown.
    static var hasSeenPasteStackHint: ConfigKey<Bool> {
        ConfigKey("guide.seen.pasteStack", default: false)
    }
}
