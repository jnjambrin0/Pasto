import AppKit
import PastoCore
import PastoSearch
import PastoUI

/// Runs the panel's search: turns the toolbar into the search field and back, feeds what the
/// user writes to the search session, offers filters for it, and shows the results in the item
/// strip.
public final class SearchController {
    /// What the strip shows for the query: the list (`idle`) or the state of the search.
    public private(set) var state = SearchSession.State.idle

    /// Called after every change of `state`.
    public var onStateChange: ((SearchSession.State) -> Void)?
    /// "Show in …" or ⌘G on a search result: the strip is on its way back to the lists, and is
    /// to show `list` with the item selected (`ItemListController.reveal(_:)`).
    public var onShowInList: ((_ item: ItemID, _ list: ListID) -> Void)?

    private let session: SearchSession
    private let suggester: SearchSuggester
    private let reader: StoreReader
    private let mainView: MainView
    private let itemList: ItemListController
    private let panel: MainWindowController

    private lazy var coordinator = SearchInputCoordinator { [weak self] in
        self?.render($0) ?? NSAttributedString()
    }
    private let suggestionsMenu = SearchSuggestionsMenu()
    private let filterBrowser = FilterBrowserPopover()
    /// Says that the search is running or found nothing, like an empty list.
    private let statusView = ListPlaceholderView(frame: .zero)
    /// Discards the search once the panel has been closed for a while.
    private var closedPanelReset: Task<Void, Never>?

    /// - Parameter panel: The panel `mainView` is the content of.
    public init(
        session: SearchSession,
        suggester: SearchSuggester,
        reader: StoreReader,
        mainView: MainView,
        itemList: ItemListController,
        panel: MainWindowController
    ) {
        self.session = session
        self.suggester = suggester
        self.reader = reader
        self.mainView = mainView
        self.itemList = itemList
        self.panel = panel

        session.onStateChange = { [weak self] in self?.show($0) }
        connectCoordinator()
        connectField()
        connectPanel()
    }

    private var toolbar: Toolbar { mainView.toolbar }
    private var searchBar: SearchBar { toolbar.searchBar }
    private var field: SearchField { searchBar.field }

    // MARK: - Activation

    /// Whether the toolbar shows the search field.
    public var isActive: Bool { toolbar.isSearchActive }

    /// Shows the search field and gives it the keyboard focus.
    public func activate() {
        guard !isActive else { return }
        toolbar.setSearchActive(true, animated: true)
        focusField()
    }

    /// Leaves the search: the query is discarded and the toolbar goes back to its tabs; the strip
    /// follows once the emptied query has settled, as any query does. The panel stays open.
    public func dismiss() {
        guard isActive else { return }
        filterBrowser.close()
        toolbar.setSearchActive(false, animated: true)
        coordinator.clear(keepingUndoHistory: false)
        hideSuggestions()
        if isFieldFocused {
            mainView.window?.makeFirstResponder(nil)
        }
    }

    private var isFieldFocused: Bool {
        mainView.window?.firstResponder === field.textView
    }

    private func focusField() {
        guard !filterBrowser.isDisplayed else { return }
        mainView.window?.makeFirstResponder(field.textView)
    }

    /// What the magnifying glass and its ⌘F do.
    private func toggle() {
        if !isActive {
            activate()
        } else if coordinator.query.isEmpty {
            dismiss()
        } else {
            focusField()
        }
    }

    /// ⌘F while the search is active walks towards the filter browser: first to the field,
    /// then into the browser, then out of it.
    private func handleFilterShortcut() {
        if filterBrowser.isDisplayed {
            filterBrowser.close()
        } else if isFieldFocused {
            showFilterBrowser()
        } else {
            focusField()
        }
    }

    // MARK: - Panel

    /// The panel finished opening: a search left active takes the keyboard focus back.
    public func panelDidShow() {
        if isActive { focusField() }
    }

    /// The panel is closing. A search left in it survives for a while, so that reopening the
    /// panel shortly after finds it; then it is discarded.
    public func panelWillClose() {
        filterBrowser.close()
        hideSuggestions()
        closedPanelReset?.cancel()
        closedPanelReset = Task { [weak self] in
            try? await Task.sleep(for: SearchMetrics.closedPanelResetDelay)
            guard !Task.isCancelled else { return }
            self?.closedPanelResetDidFire()
        }
    }

    /// A panel that is open, or on its way, keeps its search; and only a search the strip shows
    /// is discarded.
    private func closedPanelResetDidFire() {
        closedPanelReset = nil
        guard !panel.isOpen, state != .idle else { return }
        dismiss()
    }

    /// Keeps a search left in the closed panel from being discarded. The app calls it when
    /// something new is copied while the panel is closed.
    public func cancelClosedPanelReset() {
        closedPanelReset?.cancel()
        closedPanelReset = nil
    }

    private func connectPanel() {
        searchBar.onToggle = { [weak self] in self?.toggle() }
        searchBar.onFilterShortcut = { [weak self] in self?.handleFilterShortcut() }

        mainView.onTypeText = { [weak self] in self?.search(forTypedText: $0) }
        mainView.onCancel = { [weak self] in
            guard let self else { return false }
            return handleEscape(focus: .strip) != .closePanel
        }

        itemList.onShowSearchResultInList = { [weak self] id, list in self?.showResult(id, in: list) }
        mainView.collectionView.acceptsQuickPasteWithoutFocus = { [weak self] in self?.isFieldFocused == true }
    }

    /// Typing over the item strip starts a search for what was typed, replacing any query
    /// there was. A lone space does not.
    private func search(forTypedText text: String) {
        guard text != " " else { return }
        let query = SearchQuery(text: text)
        guard !query.isEmpty else { return }
        toggle()
        coordinator.setQuery(query, updatesSuggestion: true)
    }

    @discardableResult
    private func handleEscape(focus: SearchEscape.Focus) -> SearchEscape {
        let isQueryEmpty = switch focus {
        case .field: coordinator.query.isEmpty
        // The strip goes by what it shows, which follows the query once it has settled. With
        // the bar closed — just after ⌘G, while the emptied query settles — there is no search
        // left to leave.
        case .strip: !isActive || state == .idle
        }
        let action = SearchEscape.action(
            focus: focus,
            isSuggestionsMenuOpen: suggestionsMenu.isShown,
            isQueryEmpty: isQueryEmpty
        )
        switch action {
        case .closeSuggestions: hideSuggestions()
        case .clearQuery: coordinator.clear(keepingUndoHistory: true)
        case .dismissSearch: dismiss()
        case .closePanel: break
        }
        return action
    }

    /// "Show in …" or ⌘G on a result: the strip goes back to the lists, to `list`, with the item
    /// selected where its card is on screen now; the search bar closes and its query is
    /// discarded. The item is asked for first, while the strip still shows the results it is
    /// placed from.
    private func showResult(_ id: ItemID, in list: ListID) {
        onShowInList?(id, list)
        dismiss()
    }

    // MARK: - Field and query

    private func connectCoordinator() {
        coordinator.onUpdateQuery = { [weak self] in self?.queryDidChange($0) }
        coordinator.onUpdateView = { [weak self] text, selection in self?.field.show(text, selection: selection) }
        coordinator.onUpdateSuggestion = { [weak self] in self?.showSuggestions(for: $0) }
    }

    private func connectField() {
        field.onTextShouldChange = { [weak self] text, selection in
            self?.coordinator.textShouldChange(to: text, selection: selection) ?? true
        }
        field.onSelectionChange = { [weak self] in self?.coordinator.selectionDidChange($0) }
        field.onShowFilters = { [weak self] in self?.toggleFilterBrowser() }
        // Return hands the keyboard to the strip; the search stays as it is.
        field.onEnter = { [weak self] in self?.mainView.window?.makeFirstResponder(nil) }
        field.onCancel = { [weak self] in self?.handleEscape(focus: .field) }
        field.onClear = { [weak self] in self?.coordinator.clear(keepingUndoHistory: true) }
        field.onEndEditing = { [weak self] in self?.fieldDidEndEditing() }
        field.onUndo = { [weak self] in self?.coordinator.undo() ?? false }
        field.onRedo = { [weak self] in self?.coordinator.redo() ?? false }

        suggestionsMenu.onEscape = { [weak self] in self?.handleEscape(focus: .field) }
        suggestionsMenu.onLoseFocus = { [weak self] in self?.hideSuggestions() }
        filterBrowser.onWillClose = { [weak self] in self?.filterBrowserWillClose() }
    }

    /// A search field left empty is a search left: losing the focus dismisses it.
    private func fieldDidEndEditing() {
        hideSuggestions()
        if coordinator.query.isEmpty, !filterBrowser.isDisplayed {
            dismiss()
        }
    }

    private func queryDidChange(_ query: SearchQuery) {
        session.update(query)
    }

    /// The field's content for a query: its text, and a token for each filter.
    private func render(_ query: SearchQuery) -> NSAttributedString {
        SearchFieldText.attributedString(for: query, textAttributes: SearchTextView.textAttributes) { filter in
            let attachment = SearchFilterAttachment(title: title(for: filter), icon: icon(for: filter)) { [weak self] in
                self?.field.selectToken($0)
            }
            return NSAttributedString(attachment: attachment)
        }
    }

    private func title(for filter: SearchFilter) -> String {
        SearchFilterDisplay.title(
            for: filter,
            pinboardName: { [reader] in reader.list($0).map(TabBarItem.init(list:))?.name },
            now: Date(),
            calendar: .current
        )
    }

    private func icon(for filter: SearchFilter) -> SearchFilterIcon {
        SearchFilterDisplay.icon(
            for: filter,
            applicationIcon: { [reader] in reader.sourceApplication(named: $0)?.iconData },
            deviceType: { [reader] in reader.device(named: $0)?.type },
            pinboardColor: { [reader] id in
                guard case .pinboard(let color) = reader.list(id)?.attributes else { return nil }
                return color
            }
        )
    }

    // MARK: - Suggestions

    /// Offers filters for the component the cursor is on; nil, or nothing to offer, closes the
    /// menu.
    private func showSuggestions(for candidate: SearchInputCoordinator.Candidate?) {
        guard let candidate, isActive else {
            hideSuggestions()
            return
        }
        let suggestions = suggester.suggestions(for: candidate.component, in: candidate.query)
        guard !suggestions.isEmpty, let wordRect = field.rect(forCharacterRange: candidate.range) else {
            hideSuggestions()
            return
        }
        suggestionsMenu.onAccept = { [weak self] suggestion in
            // The word under the cursor becomes the filter.
            let query = candidate.query.replacingComponent(at: candidate.index, with: suggestion.filter)
            self?.coordinator.setQuery(query, updatesSuggestion: false)
        }
        suggestionsMenu.show(
            suggestions,
            icon: { [weak self] in self?.icon(for: $0) ?? .none },
            below: searchBar,
            wordRect: searchBar.convert(wordRect, from: field)
        )
    }

    private func hideSuggestions() {
        suggestionsMenu.hide()
    }

    // MARK: - Filter browser

    private func toggleFilterBrowser() {
        if filterBrowser.isDisplayed {
            filterBrowser.close()
        } else {
            showFilterBrowser()
        }
    }

    private func showFilterBrowser() {
        let model = FilterBrowserModel(
            query: coordinator.query,
            availableFilters: suggester.availableFilters(),
            // ⌥ held while opening leaves out the filters already applied.
            hidesAppliedFilters: NSEvent.modifierFlags.contains(.option),
            icon: { [weak self] in self?.icon(for: $0) ?? .none },
            onQueryChanged: { [weak self] in self?.coordinator.setQuery($0, updatesSuggestion: false) },
            onClose: { [weak self] in self?.filterBrowser.close() }
        )
        hideSuggestions()
        // If the popover takes the keyboard, the panel must not read that as losing it for good.
        panel.pendingResignKeyCloseSuppression = true
        filterBrowser.show(model, below: field.filtersButton)
        field.bounceFiltersButton()
    }

    private func filterBrowserWillClose() {
        field.bounceFiltersButton()
        // Still armed if the popover never took the keyboard.
        panel.pendingResignKeyCloseSuppression = false
        // A click in another application closes the popover without the panel noticing,
        // because the panel had already handed the keyboard to it.
        guard NSApp.isActive else {
            panel.close()
            return
        }
        if isActive, panel.isOpen {
            mainView.window?.makeFirstResponder(field.textView)
        }
    }

    // MARK: - Strip

    /// Shows a state of the search in the item strip: results replace the list, and an
    /// empty strip says whether the search is still running or found nothing. The results are
    /// live (`ItemListController.showSearchResults`): if every one of them is deleted, the
    /// strip says nothing was found.
    private func show(_ newState: SearchSession.State) {
        guard newState != state else { return }
        let wasShowingResults = state != .idle
        state = newState

        let collectionView = mainView.collectionView
        switch newState {
        case .idle:
            collectionView.emptyPlaceholderView = nil
            itemList.showSearchResults(nil)
        case .searching:
            // The results of the previous query stay on show while the new one is searched for.
            if !wasShowingResults { itemList.showSearchResults([]) }
        case .results(let ids):
            itemList.showSearchResults(ids)
        case .nothingFound:
            itemList.showSearchResults([])
        }
        if newState != .idle {
            statusView.text = newState == .searching ? SearchStrings.searching : SearchStrings.nothingFound
            collectionView.emptyPlaceholderView = statusView
        }
        announce(newState)
        onStateChange?(newState)
    }

    /// VoiceOver says what a query settled on, once per query: the focus stays in the field, so
    /// nothing else would tell. At medium priority, so that it waits for the echo of what was
    /// typed instead of cutting it short.
    private func announce(_ state: SearchSession.State) {
        let announcement: String
        switch state {
        case .idle, .searching: return
        case .results(let ids): announcement = SearchStrings.resultCount(ids.count)
        case .nothingFound: announcement = SearchStrings.nothingFound
        }
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.medium.rawValue]
        )
    }
}
