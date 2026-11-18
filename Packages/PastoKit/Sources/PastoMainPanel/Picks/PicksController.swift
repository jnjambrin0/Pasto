import AppKit
import Observation
import PastoCore
import PastoCoreUI
import PastoFoundation
import PastoPicks
import PastoSearch
import PastoUI

/// The panel's suggestions mode.
///
/// The toolbar button turns it on. The button then leaves the toolbar, the glow lights up, the
/// cards are hidden by a wave and suggestions are asked for; once they are ready — and never
/// sooner than a fixed wait — they are revealed by the reverse wave, or the strip says there
/// are none or asks for screen recording access. Changing tabs, searching, opening or closing
/// the panel and suggestions ceasing to be offered all turn it off. The panel never opens in it.
///
/// The app tells it when the panel shows and closes, when the tab or the search changes and
/// what is pasted; the rest it wires itself.
public final class PicksController {
    /// Whether the mode is on: the strip shows suggestions or is waiting for them.
    public private(set) var isActive = false

    /// The user turned the mode on: the panel's guide explains it the first time
    /// (`PanelGuideController`).
    var onTurnOn: (() -> Void)?

    /// The mode went on (true) or off (false). While it is on the tab bar shows no selected
    /// tab: the selected one loses its capsule at once and gets it back when the mode ends
    /// (`TabBar.isSelectionSuppressed`).
    public var onModeChange: ((Bool) -> Void)?

    private let provider: PicksProvider
    private let config: ConfigStore
    private let reader: StoreReader
    private let mainView: MainView
    private let itemList: ItemListController
    private let search: SearchController
    private let showScreenRecordingAccess: () -> Void

    private let glow = IntelligenceGlowView(cornerRadius: MainPanelMetrics.backgroundCornerRadius)
    private let icon = PicksIconView(side: PicksIconMetrics.toolbarSide, respondsToPointer: true)
    private let placeholder = PicksPlaceholderView(frame: .zero)
    /// Waits for the suggestions and reveals them.
    private var handover: Task<Void, Never>?
    /// The wait is over: the strip shows the suggestions.
    private var isShowingPicks = false
    private var observations: [Task<Void, Never>] = []

    /// - Parameter showScreenRecordingAccess: Presents the window that asks for screen
    ///   recording access.
    public init(
        provider: PicksProvider,
        config: ConfigStore,
        reader: StoreReader,
        mainView: MainView,
        itemList: ItemListController,
        search: SearchController,
        showScreenRecordingAccess: @escaping () -> Void
    ) {
        self.provider = provider
        self.config = config
        self.reader = reader
        self.mainView = mainView
        self.itemList = itemList
        self.search = search
        self.showScreenRecordingAccess = showScreenRecordingAccess
        connectToolbar()
        connectStrip()
        observeProvider()
    }

    isolated deinit {
        observations.forEach { $0.cancel() }
        handover?.cancel()
    }

    // MARK: - What the app reports

    /// The panel is about to show: it never opens in the mode.
    public func panelWillShow() {
        setActive(false)
        provider.panelWillShow()
    }

    /// The panel has finished showing over `destination`, the application focus goes back to
    /// when it closes: call it once that is known and before Pasto activates. Its window is
    /// looked at now.
    public func panelDidShow(destination: NSRunningApplication?) {
        provider.panelDidShow(destination: destination?.bundleIdentifier)
    }

    /// The panel starts closing, before its animation.
    public func panelWillClose() {
        provider.panelWillClose()
    }

    /// The panel has finished closing: the mode ends.
    public func panelDidClose() {
        setActive(false)
    }

    /// The user chose another tab.
    public func listDidChange() {
        setActive(false)
    }

    /// A search is showing results, or has stopped: one that is running ends the mode.
    public func searchStateDidChange(_ state: SearchSession.State) {
        if state != .idle { setActive(false) }
    }

    /// Items chosen in the strip were put on the pasteboard to be pasted.
    public func didPaste(_ ids: [ItemID]) {
        provider.didPaste(ids, from: ChoiceSource(itemList.shownCollection))
    }

    // MARK: - The mode

    private func toggle() {
        setActive(!isActive)
        if isActive { onTurnOn?() }
    }

    private func setActive(_ active: Bool) {
        guard active != isActive, !active || provider.isOffered else { return }
        isActive = active
        if active {
            activate()
        } else {
            deactivate()
        }
        onModeChange?(active)
    }

    private func activate() {
        if search.isActive { search.dismiss() }
        animateButton()
        handover?.cancel()
        glow.scene = .loading
        let strip = mainView.collectionView
        strip.performWave(from: buttonCenter(in: strip), reveal: false)
        provider.activate()
        handover = Task { [weak self] in await self?.handOver() }
    }

    /// Waits at least the minimum and until the suggestions are ready, then reveals them.
    private func handOver() async {
        // Cancelled during the wait or not, the loading check below decides.
        try? await Task.sleep(for: PicksPanelMetrics.minimumHandoverWait)
        for await isLoading in Observations({ [provider] in provider.isLoading }) where !isLoading {
            break
        }
        guard !Task.isCancelled else { return }
        isShowingPicks = true
        let strip = mainView.collectionView
        itemList.showPicks(existing(provider.items))
        strip.emptyPlaceholderView = placeholder
        glow.scene = .open
        strip.performWave(from: buttonCenter(in: strip), reveal: true)
    }

    private func deactivate() {
        handover?.cancel()
        handover = nil
        glow.scene = .closed
        let strip = mainView.collectionView
        if isShowingPicks {
            isShowingPicks = false
            itemList.showPicks(nil)
        }
        if strip.emptyPlaceholderView === placeholder {
            strip.emptyPlaceholderView = nil
        }
        strip.cancelWave()
        provider.reset()
        animateButton()
    }

    /// The button leaves the toolbar in the mode and comes back out of it. It shows the mode as
    /// selected first, at once, so that the fill is seen while it fades.
    private func animateButton() {
        let button = mainView.toolbar.suggestionsButton
        let isActivating = isActive
        button.isSelected = isActivating
        button.isHidden = !provider.isOffered
        SuggestionsButtonAnimation.run(on: button, isActive: isActivating) { [weak self] in
            guard let self, isActivating, isActive else { return }
            button.isHidden = true
        }
    }

    // MARK: - Wiring

    private func connectToolbar() {
        let toolbar = mainView.toolbar
        let button = toolbar.suggestionsButton
        button.iconView = icon
        button.onPressedChange = { [icon] in icon.isPressed = $0 }
        button.menu = makeButtonMenu()
        toolbar.onSuggestions = { [weak self] in self?.toggle() }
        toolbar.showsSuggestionsButton = provider.isOffered

        glow.isHidden = !provider.isOffered
        glow.revealOrigin = { [weak self, weak glow] in
            guard let self, let glow else { return .zero }
            return buttonCenter(in: glow)
        }
        glow.excitement = { [weak icon] in icon?.excitement ?? 0 }
        mainView.underlayView = glow
    }

    private func connectStrip() {
        mainView.collectionView.onPicksTouched = { [provider] in provider.stripTouched() }
        itemList.onShowPickInList = { [weak self] id, list in self?.showInList(id, list) }
        placeholder.onAllowAccess = showScreenRecordingAccess
        placeholder.onTurnOff = { [weak self] in self?.confirmTurnOff() }
    }

    private func observeProvider() {
        let provider = provider
        observations = [
            Task { [weak self] in
                for await isOffered in Observations({ provider.isOffered }) {
                    self?.offerDidChange(isOffered)
                }
            },
            Task { [weak self] in
                for await isMissing in Observations({ provider.isScreenAccessMissing }) {
                    self?.placeholder.showsAccessRequest = isMissing
                }
            },
            Task { [weak self] in
                for await items in Observations({ provider.items }) {
                    self?.showIfRevealed(items)
                }
            },
            // A suggested item can be deleted while it is on show.
            Task { [weak self, reader] in
                for await _ in reader.changes() {
                    guard let self else { return }
                    showIfRevealed(provider.items)
                }
            },
        ]
    }

    private func offerDidChange(_ isOffered: Bool) {
        glow.isHidden = !isOffered
        let toolbar = mainView.toolbar
        if toolbar.showsSuggestionsButton != isOffered {
            toolbar.showsSuggestionsButton = isOffered
        }
        if !isOffered { setActive(false) }
    }

    /// Suggestions that change once revealed — reranked, or one of them deleted — replace the
    /// ones on show.
    private func showIfRevealed(_ items: [ItemID]) {
        guard isShowingPicks else { return }
        itemList.showPicks(existing(items))
    }

    /// "Show in …" on a suggestion: the mode ends and the strip shows the list with the item
    /// selected where its card is now — the list under the suggestions at once, another one once
    /// its tab is chosen.
    private func showInList(_ id: ItemID, _ list: ListID) {
        itemList.focus(id, onceShowing: list)
        setActive(false)
        itemList.onShowInList?(list)
    }

    /// The items among `ids` that still exist, in the same order.
    private func existing(_ ids: [ItemID]) -> [ItemID] {
        reader.items(ids).map(\.id)
    }

    private func buttonCenter(in view: NSView) -> CGPoint {
        let button = mainView.toolbar.suggestionsButton
        return view.convert(NSPoint(x: button.bounds.midX, y: button.bounds.midY), from: button)
    }

    // MARK: - Turning off

    /// The button's context menu: a single entry that turns suggestions off.
    private func makeButtonMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.addItem(MenuItemHandler.item(title: PicksStrings.turnOffMenuItem) { [weak self] in
            self?.confirmTurnOff()
        })
        return menu
    }

    private func confirmTurnOff() {
        guard PanelAlert.confirm(
            title: PicksStrings.turnOffTitle,
            message: PicksStrings.turnOffMessage,
            action: PicksStrings.turnOff
        ) else { return }
        config.set(false, for: .isPicksEnabled)
    }
}
