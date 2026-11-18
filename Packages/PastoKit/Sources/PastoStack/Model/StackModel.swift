import Foundation
import Observation
import PastoCore
import PastoFoundation

/// The Paste Stack itself: its rows and everything that can happen to them. It knows nothing
/// about windows or views.
///
/// A stack lives from the moment its panel opens until it closes; nothing but its settings
/// outlives it.
@Observable
final class StackModel {
    typealias ItemLookup = @MainActor (_ ids: [ItemID]) -> [Item]
    typealias Paste = @MainActor (_ ids: [ItemID], _ options: RestoreOptions) -> Bool

    /// Top to bottom. ⌘V always pastes the first one.
    private(set) var rows: [StackRow] = []
    private(set) var undoSteps: [StackRowPlace] = []
    private(set) var direction: StackDirection
    /// The stack's own "Paste as Plain Text" switch.
    private(set) var isPlainTextToggleOn: Bool
    /// The app-wide "always paste as plain text" setting.
    private(set) var isGlobalPlainTextOn: Bool
    /// The app-wide "Generate Link Previews" setting: whether a link's card shows the site's icon.
    private(set) var isLinkPreviewsOn: Bool
    /// The first stack ever opened explains itself in one line above the rows.
    var showsFirstUseHint = false

    /// Called when the stack has nothing left to do and its panel should go away.
    @ObservationIgnored var onCloseRequest: (() -> Void)?

    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let hotKeys: any StackHotKeyRegistering
    @ObservationIgnored private let lookUpItems: ItemLookup
    @ObservationIgnored private let pasteItems: Paste
    @ObservationIgnored private var settingObservations: [Task<Void, Never>] = []
    /// Where the row being dragged was when its drag began.
    @ObservationIgnored private var dragOrigin: StackRowPlace?
    /// Set once the panel has closed: the stack then takes no more rows, and holds no hot keys.
    @ObservationIgnored private var isClosed = false

    /// - Parameters:
    ///   - items: The existing items among the given identifiers.
    ///   - paste: Puts the items on the pasteboard and sends the paste keystroke. Returns false
    ///     when nothing was pasted, in which case the rows stay.
    init(
        config: ConfigStore,
        hotKeys: any StackHotKeyRegistering,
        items: @escaping ItemLookup,
        paste: @escaping Paste
    ) {
        self.config = config
        self.hotKeys = hotKeys
        lookUpItems = items
        pasteItems = paste
        direction = config.value(for: .pasteStackDirection)
        isPlainTextToggleOn = config.value(for: .isPasteStackPlainTextEnabled)
        isGlobalPlainTextOn = config.value(for: .isPasteAsPlainTextEnabled)
        isLinkPreviewsOn = config.value(for: .isLinkPreviewsEnabled)

        settingObservations = [
            follow(.isPasteAsPlainTextEnabled, into: \.isGlobalPlainTextOn),
            follow(.isLinkPreviewsEnabled, into: \.isLinkPreviewsOn),
        ]
    }

    isolated deinit {
        settingObservations.forEach { $0.cancel() }
    }

    /// Either switch is enough.
    var isPlainTextOn: Bool { isPlainTextToggleOn || isGlobalPlainTextOn }

    /// How rows are written to the pasteboard, whether they are pasted or dragged out.
    var pasteOptions: RestoreOptions {
        isPlainTextOn ? .textAsPlainText : []
    }

    // MARK: - Filling

    /// New rows go in together, in the order given, at the end the direction says. Duplicates
    /// are welcome and there is no limit.
    func add(_ items: [Item]) {
        insert(items, at: direction == .top ? 0 : rows.count)
    }

    /// Rows for the given items, in the order given, at `index` — where they were dropped on the
    /// panel. An index past the end puts them last.
    func insert(_ items: [Item], at index: Int) {
        let newRows = items.map { StackRow(id: UUID(), item: $0) }
        updateRows { $0.insert(contentsOf: newRows, at: min(max(index, 0), $0.count)) }
    }

    /// Something was copied while the stack is open: it becomes a row.
    func didCapture(_ id: ItemID) {
        guard let item = lookUpItems([id]).first else { return }
        add([item])
    }

    // MARK: - Pasting

    /// ⌘V: the first row, whatever the direction.
    func pasteNext() {
        guard let first = rows.first else { return }
        paste(first.id)
    }

    /// Pastes one row. A pasted row leaves the stack, as an undo step; pasting the last one
    /// closes the stack.
    func paste(_ rowID: StackRow.ID) {
        guard let row = rows.first(where: { $0.id == rowID }), pasteItems([row.item.id], pasteOptions) else { return }
        removeRow(rowID)
        closeIfEmpty()
    }

    /// ⌃⌥⌘V: every row in one paste, top to bottom, after which the stack closes.
    func pasteAll() {
        guard !rows.isEmpty, pasteItems(rows.map(\.item.id), pasteOptions) else { return }
        updateRows { $0.removeAll() }
        onCloseRequest?()
    }

    // MARK: - Removing and undoing

    /// Takes a row out, remembering where it was. An emptied stack stays open.
    func removeRow(_ rowID: StackRow.ID) {
        guard let place = place(of: rowID) else { return }
        updateRows { $0.remove(at: place.index) }
        undoSteps.append(place)
    }

    /// Takes out every row of the given items; a stack left without rows closes.
    func remove(itemIDs: [ItemID]) {
        let itemIDs = Set(itemIDs)
        for row in rows where itemIDs.contains(row.item.id) {
            removeRow(row.id)
        }
        closeIfEmpty()
    }

    /// Puts the row removed last back where it was.
    func undo() {
        guard let place = undoSteps.popLast() else { return }
        updateRows { $0.insert(place.row, at: Self.index(for: place, in: $0)) }
    }

    // MARK: - Ordering

    /// Turns the list around and, with it, the end that new copies join. The undo steps would
    /// point at the wrong places afterwards, so they go.
    func reverseOrder() {
        updateRows { $0.reverse() }
        direction = direction.reversed
        config.set(direction, for: .pasteStackDirection)
        undoSteps.removeAll()
    }

    /// Moves a row to `index`, counted among the other rows.
    func move(_ rowID: StackRow.ID, to index: Int) {
        guard let current = rows.firstIndex(where: { $0.id == rowID }) else { return }
        let destination = min(max(index, 0), rows.count - 1)
        guard destination != current else { return }
        updateRows { rows in
            let row = rows.remove(at: current)
            rows.insert(row, at: destination)
        }
    }

    // MARK: - Dragging

    /// A row starts being dragged: where it is now is where a drag that comes to nothing puts it
    /// back. Meanwhile the drag moves it around with `move`.
    func beginDrag(_ rowID: StackRow.ID) {
        dragOrigin = place(of: rowID)
    }

    /// The drag of a row is over. Given up, the row goes back to where it started; dropped on the
    /// panel, it stays where the drag left it; dropped on another application, it leaves the
    /// stack as an undo step that puts it back where it started, and a stack left without rows
    /// closes. A row that left the stack meanwhile — pasted, or its item deleted — is left alone.
    func endDrag(_ outcome: StackDragOutcome) {
        guard let origin = dragOrigin else { return }
        dragOrigin = nil
        guard let current = rows.firstIndex(where: { $0.id == origin.row.id }) else { return }

        switch outcome {
        case .cancelled:
            var others = rows
            let row = others.remove(at: current)
            guard Self.index(for: origin, in: others) != current else { return }
            updateRows { rows in
                rows.remove(at: current)
                rows.insert(row, at: Self.index(for: origin, in: rows))
            }
        case .droppedInPanel:
            break
        case .droppedOutside:
            let row = rows[current]
            updateRows { $0.remove(at: current) }
            undoSteps.append(StackRowPlace(row: row, rowAboveID: origin.rowAboveID, index: origin.index))
            closeIfEmpty()
        }
    }

    // MARK: - Plain text

    func togglePlainText() {
        isPlainTextToggleOn.toggle()
        config.set(isPlainTextToggleOn, for: .isPasteStackPlainTextEnabled)
    }

    // MARK: - Store changes

    /// Brings the rows up to date with the store: rows and undo steps of deleted items go, the
    /// others take the item's current value. Losing every row this way does not close the stack.
    func reconcileWithStore() {
        let referenced = Set(rows.map(\.item.id)).union(undoSteps.map(\.row.item.id))
        guard !referenced.isEmpty else { return }
        let current = Dictionary(lookUpItems(Array(referenced)).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let currentRows = rows.compactMap { row in
            current[row.item.id].map { StackRow(id: row.id, item: $0) }
        }
        if currentRows != rows {
            updateRows { $0 = currentRows }
        }
        let currentSteps = undoSteps.compactMap { step in
            current[step.row.item.id].map {
                StackRowPlace(row: StackRow(id: step.row.id, item: $0), rowAboveID: step.rowAboveID, index: step.index)
            }
        }
        if currentSteps != undoSteps {
            undoSteps = currentSteps
        }
    }

    // MARK: - Closing

    /// Lets go of everything the stack holds outside itself. Called once, when its panel closes;
    /// whatever arrives afterwards — the end of a drag, an item dropped a moment before — changes
    /// nothing.
    func tearDown() {
        isClosed = true
        settingObservations.forEach { $0.cancel() }
        StackHotKey.allCases.forEach { hotKeys.unregister(caller: $0.caller) }
        undoSteps.removeAll()
    }

    private func closeIfEmpty() {
        if rows.isEmpty { onCloseRequest?() }
    }

    // MARK: - Places

    private func place(of rowID: StackRow.ID) -> StackRowPlace? {
        guard let index = rows.firstIndex(where: { $0.id == rowID }) else { return nil }
        return StackRowPlace(row: rows[index], rowAboveID: index > 0 ? rows[index - 1].id : nil, index: index)
    }

    /// Where a row goes back to: under the row it used to follow if that one is still in `rows`,
    /// otherwise at its old index, as far as `rows` still reaches.
    private static func index(for place: StackRowPlace, in rows: [StackRow]) -> Int {
        if let rowAboveID = place.rowAboveID, let above = rows.firstIndex(where: { $0.id == rowAboveID }) {
            above + 1
        } else {
            min(place.index, rows.count)
        }
    }

    // MARK: - Hot keys

    /// Every change of the rows goes through here, so that ⌘V and ⌃⌥⌘V belong to the stack
    /// exactly while there is something to paste: with no rows, ⌘V is the system's again.
    private func updateRows(_ change: (inout [StackRow]) -> Void) {
        guard !isClosed else { return }
        change(&rows)
        if rows.isEmpty {
            StackHotKey.allCases.forEach { hotKeys.unregister(caller: $0.caller) }
        } else {
            hotKeys.register(StackHotKey.pasteNext.shortcut, caller: StackHotKey.pasteNext.caller) { [weak self] in
                self?.pasteNext()
            }
            hotKeys.register(StackHotKey.pasteAll.shortcut, caller: StackHotKey.pasteAll.caller) { [weak self] in
                self?.pasteAll()
            }
        }
    }

    // MARK: - Settings

    /// Keeps `property` equal to an app-wide setting for as long as the stack lives.
    private func follow(_ key: ConfigKey<Bool>, into property: ReferenceWritableKeyPath<StackModel, Bool>) -> Task<Void, Never> {
        Task { [weak self, config] in
            for await value in config.values(for: key) {
                guard let self else { return }
                if self[keyPath: property] != value { self[keyPath: property] = value }
            }
        }
    }
}
