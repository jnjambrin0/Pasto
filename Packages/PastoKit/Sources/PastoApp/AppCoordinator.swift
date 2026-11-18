import AppKit
import Carbon.HIToolbox
import os
import PastoCore
import PastoCoreUI
import PastoFoundation
import PastoInput
import PastoMainPanel
import PastoOnboarding
import PastoPermissions
import PastoPicks
import PastoPreview
import PastoSearch
import PastoSettings
import PastoStack
import PastoStatusItem
import PastoUI
import PastoUpdates
import SwiftUI

/// Owns the app-level flows: opening the panel, handing focus back, pasting and copying.
final class AppCoordinator {
    #if DEBUG
    /// Debug builds only: an empty shortcut falls back to ⌃⇧⌘V / ⌃⇧⌘C, so that a development
    /// build stays reachable next to an installed Pasto or another clipboard manager holding ⇧⌘V
    /// and ⇧⌘C. In Release an empty shortcut is no shortcut: the user cleared it, or something
    /// else already had both initial choices.
    private static let developmentActivationShortcut: Shortcut? = Shortcut(
        keyCode: kVK_ANSI_V,
        modifiers: [.command, .shift, .control]
    )
    private static let developmentStackShortcut: Shortcut? = Shortcut(
        keyCode: kVK_ANSI_C,
        modifiers: [.command, .shift, .control]
    )
    #else
    private static let developmentActivationShortcut: Shortcut? = nil
    private static let developmentStackShortcut: Shortcut? = nil
    #endif
    private static let activationCaller = "activation"
    private static let stackCaller = "pasteStackShortcut"

    private let log = Log.logger(.app)
    private let services: Services
    private let hotKeys = HotKeyCenter()
    private let mainView = MainView()
    private let panel: MainWindowController
    private let itemList: ItemListController
    private let listTabs: ListTabsController
    private let search: SearchController
    private let picksController: PicksController
    private let guide: PanelGuideController
    private let soundFeedback: SoundFeedback
    private let pauseController: PauseController
    private let appMenu: AppMenu
    private let screenSharingPrivacy: ScreenSharingPrivacyManager
    private let settings: SettingsWindowController
    private let menuRequests: MenuRequests
    private let problemReporter = ProblemReporter()
    /// Whether Help › Getting Started has the welcome screens on show.
    private var isShowingGettingStarted = false
    /// Brings Pasto back after System Settings quits it to apply screen recording access.
    private let relauncher: ScreenRecordingRelauncher
    /// Pasto came back after a screen recording grant and is taking the user back to where they
    /// asked: a "reopen" meanwhile — System Settings reopening Pasto as well — does not open the
    /// panel over it.
    private var isResumingScreenRecording = false
    private let stack: StackWindowManager
    private let permissions: SystemPermissionsPresenter
    private let notices: NoticeCoordinator
    private let about = AboutWindowPresenter()
    private let noticeCards: NoticeCardsController
    private var preview: ItemPreviewCoordinator?
    private var stackShortcut: Shortcut?
    private var settingsObservations: [Task<Void, Never>] = []
    private var statusItem: StatusItem?

    private var framePacingMonitor: FramePacingMonitor?
    /// The application the user was in when the panel opened; reactivated when it closes and the
    /// one that receives the paste.
    private var previousApplication: NSRunningApplication?
    private var isShowingResultInList = false

    init(services: Services) {
        self.services = services
        panel = MainWindowController(contentView: mainView)
        listTabs = ListTabsController(
            reader: services.reader,
            writer: services.writer,
            itemWriter: services.itemWriter,
            config: services.config,
            toolbar: mainView.toolbar
        )
        itemList = ItemListController(
            reader: services.reader,
            writer: services.itemWriter,
            config: services.config,
            collectionView: mainView.collectionView,
            cellEnvironment: ItemCellEnvironment(imageDecoder: ImageDecoder()),
            list: listTabs.selectedList
        )
        search = SearchController(
            session: SearchSession(service: SearchService(index: services.searchIndex, reader: services.reader)),
            suggester: SearchSuggester(dataSource: StoreSuggestionDataSource(reader: services.reader)),
            reader: services.reader,
            mainView: mainView,
            itemList: itemList,
            panel: panel
        )
        soundFeedback = SoundFeedback(config: services.config)
        pauseController = PauseController(historyManager: services.historyManager)
        let permissions = SystemPermissionsPresenter(config: services.config)
        self.permissions = permissions
        relauncher = ScreenRecordingRelauncher(config: services.config)
        picksController = PicksController(
            provider: services.picks,
            config: services.config,
            reader: services.reader,
            mainView: mainView,
            itemList: itemList,
            search: search,
            showScreenRecordingAccess: { permissions.showScreenRecordingAccess(from: .panel) }
        )
        guide = PanelGuideController(config: services.config, mainView: mainView, picks: picksController)
        let noticeRepository = NoticeRepository(config: services.config)
        let notices = NoticeCoordinator(
            repository: noticeRepository,
            config: services.config,
            permissions: permissions
        )
        self.notices = notices
        noticeCards = NoticeCardsController(
            repository: noticeRepository,
            collectionView: mainView.collectionView,
            closeButtonLabel: NoticeCoordinator.closeButtonLabel,
            onAction: { [notices] in notices.perform($0) },
            onClose: { noticeRepository.remove(id: $0) }
        )
        let settings = SettingsWindowController(
            config: services.config,
            reader: services.reader,
            writer: services.writer,
            hotKeys: hotKeys,
            requestAccessibilityAccess: { _ = permissions.requestAccessibilityAccess() }
        )
        self.settings = settings
        notices.openShortcutSettings = { settings.show(.shortcuts) }
        settings.suggestions = SuggestionsAvailability(
            isSupported: services.picks.isSupported,
            isModelEnabled: { [picks = services.picks] in picks.isModelEnabled },
            isScreenAccessMissing: { [picks = services.picks] in picks.isScreenAccessMissing },
            requestScreenAccess: { permissions.showScreenRecordingAccess(from: .settings) }
        )
        // Erasing or shortening the history cannot be undone, nor anything done before it.
        settings.onIrreversibleItemChange = { [itemWriter = services.itemWriter] in itemWriter.removeAllActions() }
        // What suggestions learnt from the history goes with it.
        settings.onEraseHistory = { [picks = services.picks] in Task { await picks.eraseData() } }
        settings.onRemoveAllData = { [searchIndex = services.searchIndex, picks = services.picks] in
            Task { await DataRemoval.removeEverythingAndQuit(searchIndex: searchIndex, picks: picks) }
        }
        stack = StackWindowManager(
            dependencies: StackDependencies(
                items: { [reader = services.reader] in reader.items($0) },
                paste: { [restorer = services.restorer, config = services.config, picks = services.picks] ids, options in
                    // The stack pastes into the active app whatever the "paste items" setting says.
                    guard AccessibilityAccess.isGranted else {
                        // Without access the row stays; the user is asked what to do instead, as
                        // when pasting from the panel.
                        guard NSApp.modalWindow == nil else {
                            NSApp.activate(ignoringOtherApps: true)
                            return false
                        }
                        NSApp.activate(ignoringOtherApps: true)
                        switch permissions.askToPasteToOtherApps() {
                        case .enableAccessibilityAccess:
                            _ = permissions.requestAccessibilityAccess()
                        case .copyToClipboard(let doNotAskAgain):
                            if doNotAskAgain {
                                config.set(false, for: .isDirectPasteEnabled)
                            }
                            _ = restorer.restore(ids, options: options)
                            picks.didPaste(ids, from: .list)
                        }
                        return false
                    }
                    // Suggestions hear of it whatever the outcome.
                    let isRestored = restorer.restore(ids, options: options)
                    picks.didPaste(ids, from: .list)
                    guard isRestored else {
                        NSSound.beep()
                        return false
                    }
                    Task { SyntheticKeystroke.postPaste() }
                    return true
                },
                copy: {
                    guard AccessibilityAccess.isGranted else {
                        if NSApp.modalWindow == nil {
                            _ = permissions.requestAccessibilityAccess()
                        } else {
                            NSApp.activate(ignoringOtherApps: true)
                        }
                        return false
                    }
                    // The stack opens once the copy has been asked for, sent or not.
                    SyntheticKeystroke.postCopy()
                    return true
                },
                captureEvents: { [historyManager = services.historyManager] in await historyManager.events() },
                storeChanges: { [reader = services.reader] in reader.changes() },
                draggingContents: { [restorer = services.restorer] ids, options in
                    restorer.draggingContents(of: ids, options: options)
                },
                record: { [writer = services.writer] pasteboardItems in
                    guard let item = await NewItem.captured(from: pasteboardItems, at: Date()) else { return nil }
                    return try? await writer.perform(author: .user) { try $0.record(item).id }
                }
            ),
            config: services.config,
            hotKeys: hotKeys
        )
        let menuRequests = MenuRequests()
        self.menuRequests = menuRequests
        screenSharingPrivacy = ScreenSharingPrivacyManager(config: services.config)
        appMenu = AppMenu(
            pauseController: pauseController,
            showAbout: { [about] in
                menuRequests.willShowWindow?()
                about.show()
            },
            checkForUpdates: { [updates = services.updates] in
                menuRequests.willShowWindow?()
                updates.checkForUpdates()
            },
            canCheckForUpdates: { [updates = services.updates] in updates.canCheckForUpdates },
            showSettings: {
                menuRequests.willShowWindow?()
                settings.show()
            },
            createTextItem: { menuRequests.createTextItem?() },
            help: AppMenu.HelpActions(
                showGettingStarted: { menuRequests.showGettingStarted?() },
                showKeyboardShortcuts: {
                    menuRequests.willShowWindow?()
                    settings.show(.shortcuts)
                },
                reportProblem: { [problemReporter] in
                    menuRequests.willShowWindow?()
                    problemReporter.run()
                },
                showAcknowledgements: { [about] in
                    menuRequests.willShowWindow?()
                    about.showAcknowledgements()
                },
                showTips: { menuRequests.showTips?() }
            )
        )
    }

    /// Brings the app up in order: the welcome flow first, on a first launch, and only then the
    /// menu bar icon, the shortcuts and capture — nothing is captured while the welcome flow is
    /// showing.
    /// - Parameter wasLaunchedAsLoginItem: Read by the caller while the launch event is still
    ///   current; by the time this task runs it no longer is.
    func start(wasLaunchedAsLoginItem: Bool) async {
        let config = services.config
        // From the start: System Settings may quit Pasto for a grant at any point after this.
        relauncher.start()
        // Development runs with a store in memory go straight to the app.
        let plan = DebugArguments.usesInMemoryStore
            ? nil
            : LaunchPlan(lastLaunchedVersion: config.lastLaunchedVersion, currentVersion: Self.currentVersion)
        // Read before anything can change the access or the request: whether System Settings
        // has just reopened Pasto for a screen recording grant, and where the user asked from.
        let screenRecordingOrigin = takeScreenRecordingResumption()
        var onboardingFinish: ContinuousClock.Instant?

        if wasLaunchedAsLoginItem {
            try? await Task.sleep(for: LaunchTimings.loginItemDelay)
        }
        screenSharingPrivacy.start()
        // Once per installation, before Quick Start shows the activation shortcut. Runs with a
        // store in memory leave the user's settings alone.
        if plan != nil {
            InitialShortcuts.apply(to: config, hotKeys: hotKeys)
        }
        if plan?.runsOnboarding == true {
            NSApp.mainMenu = MainMenu.makeForOnboarding()
            NSApp.setActivationPolicy(.regular)
            let onboarding = OnboardingWindowPresenter(
                config: config, reader: services.reader, writer: services.writer, hotKeys: hotKeys,
                suggestions: onboardingSuggestions
            )
            await onboarding.run()
            onboardingFinish = onboarding.finishInstant
            // The panel never opens empty the first time.
            await WelcomeContentSeeder(config: config, writer: services.writer).seedIfNeeded()
            notices.seedAfterOnboarding()
            NSApp.setActivationPolicy(.accessory)
        }
        NSApp.mainMenu = MainMenu.make(appMenu: appMenu)
        // Once the definitive main menu is in place.
        services.updates.start()

        // Before Pasto holds its shortcuts, which would make them look free: one that something
        // else has now may not open the panel, or the Stack, and a card says so.
        let takenShortcuts = plan == nil ? [] : InitialShortcuts.takenShortcuts(in: config, hotKeys: hotKeys)
        connect()
        notices.start()
        notices.shortcutsAreTaken(takenShortcuts.compactMap { config.shortcut(for: $0).map { ShortcutDisplay.string(for: $0) } })
        if plan != nil {
            config.recordLaunch(of: Self.currentVersion)
        }
        startCapture()

        if plan?.showsPanelWhenFinished == true || DebugArguments.showsPanelAtLaunch {
            try? await Task.sleep(for: LaunchTimings.panelRevealDelay)
            if NSApp.modalWindow != nil {
                NSApp.activate(ignoringOtherApps: true)
            } else if !panel.isOpen {
                picksController.panelWillShow()
                panel.toggle()
            }
            if let onboardingFinish {
                let elapsed = (ContinuousClock.now - onboardingFinish).components
                let milliseconds = elapsed.seconds * 1000 + elapsed.attoseconds / 1_000_000_000_000_000
                log.info("Onboarding: last step → panel in \(milliseconds, privacy: .public) ms")
            }
        }
        if let screenRecordingOrigin {
            resumeScreenRecording(from: screenRecordingOrigin, welcomeRan: plan?.runsOnboarding == true)
        }
    }

    /// What the welcome's suggestions step needs; none on a Mac that cannot run suggestions.
    private var onboardingSuggestions: OnboardingSuggestions? {
        guard services.picks.isSupported else { return nil }
        return OnboardingSuggestions { [picks = services.picks] in picks.isAppleIntelligenceOn }
    }

    /// Whether this launch is System Settings reopening Pasto after the user granted screen
    /// recording access, and if so where they asked from. A request that is too old is forgotten;
    /// one honoured now too, unless the access has still not arrived.
    private func takeScreenRecordingResumption() -> ScreenRecordingRequest.Origin? {
        let config = services.config
        guard let request = config.screenRecordingRequest else { return nil }
        let isGranted = ScreenRecordingAccess.isGranted
        switch request.resumption(at: Date(), isGranted: isGranted) {
        case .discard:
            config.clearScreenRecordingRequest()
            return nil
        case .keep:
            return nil
        case .resume(let origin, let keepsRequest):
            log.notice("Back after a screen recording request from \(origin.rawValue, privacy: .public); granted: \(isGranted, privacy: .public)")
            if keepsRequest {
                var request = request
                request.relaunchDate = nil
                config.set(JSONConfigValue(request), for: .screenRecordingRequest)
            } else {
                config.clearScreenRecordingRequest()
            }
            return origin
        }
    }

    /// Takes the user back to where they asked for screen recording access. The welcome comes
    /// back to its suggestions step by itself (first launch) or is shown again there (Getting
    /// Started); from the panel or Settings, the access window finishes the job — the capture
    /// check that brings up macOS's confirmation — and then the panel, or Settings › Intelligence,
    /// shows. A welcome that has been finished since the request goes the panel's way.
    /// - Parameter welcomeRan: The first launch's welcome ran in this launch and has dealt with it.
    private func resumeScreenRecording(from origin: ScreenRecordingRequest.Origin, welcomeRan: Bool) {
        switch origin {
        case .onboarding where welcomeRan:
            break
        case .gettingStarted where services.config.isWelcomeOnSuggestionsStep:
            showGettingStarted(resumesSavedStep: true)
        case .onboarding, .gettingStarted, .panel, .settings:
            isResumingScreenRecording = true
            permissions.showScreenRecordingAccess(from: origin == .settings ? .settings : .panel) { [weak self] in
                guard let self else { return }
                isResumingScreenRecording = false
                if origin == .settings {
                    settings.show(.intelligence)
                } else if !panel.isOpen, NSApp.modalWindow == nil {
                    togglePanel()
                }
            }
        }
    }

    private static var currentVersion: AppVersion {
        AppVersion(bundle: .main) ?? AppVersion(major: 0, minor: 0, patch: 0)
    }

    /// Wires the parts together and puts the menu bar icon and the shortcuts in place.
    private func connect() {
        itemList.onPaste = { [weak self] ids, plainText, forcesDirectPaste in
            self?.paste(ids, plainText: plainText, forcesDirectPaste: forcesDirectPaste)
        }
        itemList.onCopy = { [weak self] ids, plainText in self?.copy(ids, plainText: plainText) }
        itemList.onShowInList = { [weak self] in self?.listTabs.select($0) }
        itemList.draggingContents = { [restorer = services.restorer] ids, options in
            restorer.draggingContents(of: ids, options: options)
        }
        panel.contentUndoManager = services.itemWriter.undoManager
        connectPreview()
        itemList.isPasteStackVisible = { [stack] in stack.isVisible }
        itemList.onCreateStack = { [stack] ids in
            stack.add(ids)
            NSApp.deactivate()
        }
        observeSettings()
        menuRequests.showGettingStarted = { [weak self] in self?.showGettingStarted() }
        menuRequests.showTips = { [weak self] in
            guard let self else { return }
            guide.showTipsAgain()
            if !panel.isOpen { togglePanel() }
        }
        panel.onDidShow = { [weak self] in self?.panelDidShow() }
        panel.onWillClose = { [weak self] in self?.panelWillClose() }

        listTabs.onSelect = { [weak self] in
            // Choosing a tab leaves the search, which closes and empties its bar; "Show in" does
            // so itself, after the item has been placed from the results.
            if self?.isShowingResultInList == false { self?.search.dismiss() }
            self?.itemList.show($0)
            self?.picksController.listDidChange()
        }
        listTabs.onEraseHistory = { [picks = services.picks] in Task { await picks.eraseData() } }
        panel.onDidClose = { [weak self] in self?.picksController.panelDidClose() }
        // In suggestions mode no tab is the one on show.
        picksController.onModeChange = { [toolbar = mainView.toolbar] in toolbar.tabBar.isSelectionSuppressed = $0 }
        search.onStateChange = { [weak self] in self?.picksController.searchStateDidChange($0) }
        search.onShowInList = { [weak self] id, list in
            self?.isShowingResultInList = true
            defer { self?.isShowingResultInList = false }
            self?.listTabs.select(list)
            self?.itemList.reveal(id)
        }
        mainView.toolbar.moreMenuProvider = { [appMenu] in appMenu.makeMenu() }
        let statusItem = StatusItem(
            config: services.config,
            onClick: { [weak self] in self?.togglePanel() },
            menuProvider: { [appMenu] in appMenu.makeMenu() }
        )
        statusItem.pausedAccessibilityValue = AppStrings.pausedShort
        mainView.toolbar.pauseMenuProvider = { [appMenu] in appMenu.makePauseMenu() }
        pauseController.onChange = { [weak self, weak statusItem] in
            guard let self else { return }
            statusItem?.isPaused = pauseController.isPaused
            mainView.toolbar.pauseStatus = pauseController.isPaused ? .paused(until: pauseController.resumeDate) : .running
        }
        self.statusItem = statusItem

        if let frameLogURL = DebugArguments.frameLogURL {
            framePacingMonitor = FramePacingMonitor(logURL: frameLogURL)
        }

    }

    private func startCapture() {
        // Writes that keep failing — a full disk — lose what is copied: a card says so. Followed
        // from before the first capture.
        let writeOutcomes = services.writer.outcomes()
        Task { [weak self] in
            for await outcome in writeOutcomes {
                switch outcome {
                case .saved: self?.notices.storeWriteDidSucceed()
                case .failed: self?.notices.storeWriteDidFail()
                }
            }
        }
        // In the same turn as the pasteboard write, before the keystroke.
        services.restorer.onRestore = { [soundFeedback] _ in soundFeedback.playPaste() }
        Task { [weak self, restorer = services.restorer] in
            for await _ in restorer.events() {
                // Nothing done before a restore can be undone after it.
                self?.services.itemWriter.removeAllActions()
            }
        }
        Task { [weak self, services] in
            if let count = DebugArguments.syntheticItemCount {
                await SyntheticItems.insert(count, into: services.writer)
            }
            // The index knows which store it describes and rebuilds itself when that changes,
            // so development runs with a store in memory can use it too.
            await services.startIndexing()
            let events = await services.historyManager.events()
            services.picks.start(captures: await services.historyManager.events())
            await services.historyManager.start()
            for await event in events {
                self?.handle(event)
            }
        }
    }

    private func handle(_ event: CaptureEvent) {
        switch event {
        case .captured(let capture):
            notices.pasteboardAccessIsWorking()
            statusItem?.captureBlockedReason = nil
            // Nor can anything done before a capture.
            services.itemWriter.removeAllActions()
            soundFeedback.playCopy(wasInHistory: capture.wasInHistory, isPasteStackVisible: stack.isVisible)
            if capture.didChangeNewestItem {
                statusItem?.animateCapture()
                // A new clip while the panel is closed brings it back to the history, so the
                // next time it opens it shows what was just copied.
                if !panel.isOpen {
                    listTabs.select(.clipboard)
                    search.cancelClosedPanelReset()
                }
                itemList.didCaptureNewestItem(capture.itemID)
            }
        case .pasteboardAccessNeeded:
            // Every refused read reports it, so every copy: the window that asks for access
            // goes up once per launch at most, and the card and the icon remind afterwards.
            log.info("Pasteboard access is not set to always allow: nothing is captured")
            statusItem?.captureBlockedReason = AppStrings.pasteboardAccessMissing
            notices.pasteboardAccessIsMissing(isPanelOpen: panel.isOpen)
        }
    }

    // MARK: - Panel

    /// Pasto opened again from Finder, the Dock or Spotlight while running: it has no window
    /// to bring forward and its icon may be hidden, so the panel shows. Not before the launch has
    /// put it in place, and an open panel stays open.
    func reopen() {
        guard statusItem != nil, !panel.isOpen, !isResumingScreenRecording else { return }
        togglePanel()
    }

    private func togglePanel() {
        // With a modal window up, or the welcome screens, bring the app forward instead of
        // opening the panel over them.
        if !panel.isOpen, NSApp.modalWindow != nil || isShowingGettingStarted {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        if !panel.isOpen { picksController.panelWillShow() }
        panel.toggle()
    }

    /// Once the panel is in place Pasto becomes the active application, so the panel behaves like
    /// a regular key window; the application it displaced is remembered to hand focus back.
    private func panelDidShow() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        if let frontmost, frontmost.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApplication = frontmost
        }
        // Before Pasto activates: suggestions look at the window focus will go back to.
        picksController.panelDidShow(destination: previousApplication)
        // A cooperative request the system may decline. Either way the menu bar stays the
        // previous app's: an accessory app has none.
        NSApp.activate()
        setStackHotKeyRegistered(false)
        search.panelDidShow()
        framePacingMonitor?.start(in: mainView)
        announcePanel()
        guide.panelDidShow()
    }

    /// VoiceOver says which list the panel shows and how long it is, then reads the selected
    /// card, which has the focus.
    private func announcePanel() {
        guard NSWorkspace.shared.isVoiceOverEnabled else { return }
        let collectionView = mainView.collectionView
        let list = collectionView.accessibilityLabel() ?? ""
        let announcement = AppStrings.panelAnnouncement(list: list, itemCount: itemList.numberOfCells(in: collectionView))
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [.announcement: announcement, .priority: NSAccessibilityPriorityLevel.high.rawValue]
        )
        if let window = collectionView.window {
            NSAccessibility.post(element: window, notification: .focusedUIElementChanged)
        }
    }

    // MARK: - Help

    /// Help › Getting Started: the welcome screens again, from the first, with the settings as
    /// they are. Capture and the shortcuts go on meanwhile; the panel waits until the window is
    /// gone.
    /// - Parameter resumesSavedStep: Back on the step it was on — the suggestions step, after
    ///   System Settings quit and reopened Pasto for a screen recording grant.
    private func showGettingStarted(resumesSavedStep: Bool = false) {
        guard !isShowingGettingStarted, NSApp.modalWindow == nil else {
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        isShowingGettingStarted = true
        previousApplication = nil
        Task { [weak self, services, hotKeys, onboardingSuggestions] in
            NSApp.setActivationPolicy(.regular)
            let onboarding = OnboardingWindowPresenter(
                config: services.config, reader: services.reader, writer: services.writer, hotKeys: hotKeys,
                suggestions: onboardingSuggestions, isReplay: true, resumesReplay: resumesSavedStep
            )
            await onboarding.run()
            NSApp.setActivationPolicy(.accessory)
            self?.isShowingGettingStarted = false
        }
    }

    /// Hands activation back before the closing animation starts. Yielding activation is the
    /// cooperative way to do it; the "ignoring other apps" option has had no effect since
    /// macOS 14.
    private func panelWillClose() {
        guide.panelWillClose()
        picksController.panelWillClose()
        setStackHotKeyRegistered(true)
        search.panelWillClose()
        _ = preview?.closePreview()
        // An editing or preview window took over: the previous app must not come forward.
        if preview?.hasOpenWindows == true {
            previousApplication = nil
        }
        guard let previousApplication else { return }
        NSApp.yieldActivation(to: previousApplication)
        previousApplication.activate(from: .current)
        self.previousApplication = nil
    }

    // MARK: - Items

    // MARK: - Preview and editing

    private func connectPreview() {
        let preview = ItemPreviewCoordinator(
            reader: services.reader,
            writer: services.writer,
            itemWriter: services.itemWriter,
            config: services.config,
            handlers: PreviewHandlers(
                pinMenu: { [itemList] in itemList.pinMenu(for: $0) },
                share: { [itemList] id, anchor in itemList.showSharingPicker(for: id, anchoredTo: anchor) },
                open: { NSWorkspace.shared.open($0) },
                closePanel: { NSApp.deactivate() },
                showList: { [weak self] list in
                    // The panel has closed by now: show the list in it again.
                    guard let self else { return }
                    listTabs.select(list)
                    if !panel.isOpen, NSApp.modalWindow == nil {
                        togglePanel()
                    }
                },
                fetchLinkMetadata: { [historyManager = services.historyManager] url, id in
                    Task { await historyManager.fetchLinkMetadata(of: url, for: id) }
                }
            )
        )
        self.preview = preview

        itemList.onPreview = { [itemList] id in
            itemList.bringCellIntoView(for: id) { card in
                guard let card else { return NSSound.beep() }
                preview.togglePreview(of: id, anchoredTo: card)
            }
        }
        // An open preview follows the selection to the next card.
        itemList.onSelectedItemChange = { id, card in preview.showSelectedItem(id, anchoredTo: card) }
        mainView.collectionView.copyWhilePreviewing = {
            guard preview.isPreviewVisible else { return false }
            preview.closePreviewAfterCopy()
            return true
        }
        itemList.onEdit = { preview.edit($0) }
        if ItemPreviewCoordinator.isWritingToolsAvailable {
            itemList.onWritingTools = { preview.editWithWritingTools($0) }
        }
        mainView.onEscape = { preview.closePreview() }
        menuRequests.willShowWindow = { [weak self] in self?.previousApplication = nil }
        menuRequests.createTextItem = { [weak self] in
            preview.showNewTextItem(in: self?.listTabs.selectedList)
        }
    }

    // MARK: - Settings

    /// Applies the settings the app itself acts on, now and whenever they change.
    private func observeSettings() {
        let collectionView = mainView.collectionView
        let tabBar = mainView.toolbar.tabBar

        observe(.activationShortcut) { [weak self] shortcut in
            self?.registerActivationShortcut(shortcut.value)
        }
        observe(.pasteStackShortcut) { [weak self] shortcut in
            self?.registerStackShortcut(shortcut.value)
        }
        observe(.nextPinboardShortcut) { tabBar.nextPinboardShortcut = $0.value }
        observe(.previousPinboardShortcut) { tabBar.previousPinboardShortcut = $0.value }
        observe(.plainTextModifierFlags) { [weak self] flags in
            let flags = NSEvent.ModifierFlags(rawValue: UInt(flags))
            collectionView.plainTextModifierFlags = flags
            self?.itemList.cellEnvironment.plainTextModifierFlags = flags
        }
        observe(.quickPasteModifierFlags) { [weak self] flags in
            let flags = NSEvent.ModifierFlags(rawValue: UInt(flags))
            collectionView.quickPasteModifierFlags = flags
            self?.itemList.cellEnvironment.quickPasteModifierFlags = flags
        }
        observe(.isLinkPreviewsEnabled) { [weak self] in self?.itemList.cellEnvironment.isLinkPreviewsEnabled = $0 }
    }

    private func observe<Value>(_ key: ConfigKey<Value>, _ apply: @escaping (Value) -> Void) {
        settingsObservations.append(Task { [config = services.config] in
            for await value in config.values(for: key) {
                apply(value)
            }
        })
    }

    /// The same shortcut opens the stack from anywhere and, inside the panel, makes a stack of
    /// the selection. Without one, neither happens (Debug builds keep a fallback).
    private func registerStackShortcut(_ shortcut: Shortcut?) {
        let shortcut = shortcut ?? Self.developmentStackShortcut
        stackShortcut = shortcut
        setStackHotKeyRegistered(!panel.isOpen)
        mainView.collectionView.createStackShortcut = shortcut.map { ($0.keyCode, $0.modifiers) }
        mainView.collectionView.createStackKeyEquivalent = shortcut.flatMap { shortcut in
            CGKeyCode(exactly: shortcut.keyCode).flatMap(KeyCodeResolver.character(for:))
                .map { KeyEquivalent(String($0), modifiers: shortcut.modifiers) }
        }
    }

    /// A hot key swallows its keystroke, so while the panel is open it is given up: the panel
    /// then sees the key itself and makes a stack of the selection.
    private func setStackHotKeyRegistered(_ isRegistered: Bool) {
        // Registering replaces the caller's previous hot key once the new one is in place.
        guard isRegistered, let stackShortcut else {
            hotKeys.unregister(caller: Self.stackCaller)
            return
        }
        hotKeys.register(stackShortcut, caller: Self.stackCaller) { [weak self] in
            self?.stack.activate()
        }
    }

    /// An empty activation shortcut is no shortcut: the panel then opens from the menu bar icon
    /// only (Debug builds keep a fallback).
    private func registerActivationShortcut(_ shortcut: Shortcut?) {
        guard let shortcut = shortcut ?? Self.developmentActivationShortcut else {
            hotKeys.unregister(caller: Self.activationCaller)
            return
        }
        hotKeys.register(shortcut, caller: Self.activationCaller) { [weak self] in
            self?.togglePanel()
        }
    }

    /// Pastes in one synchronous turn, in this order: put the items on the pasteboard, queue the
    /// keystroke for the next main-actor turn, deactivate. Losing key status closes the panel,
    /// which hands focus back to the previous application; by the time the queued keystroke is
    /// posted that application is frontmost again. There are no delays.
    private func paste(_ ids: [ItemID], plainText: Bool, forcesDirectPaste: Bool) {
        let config = services.config
        let gesture: RestoreOptions = plainText ? .plainText : []
        let options = gesture.applying(alwaysPlainText: config.value(for: .isPasteAsPlainTextEnabled))

        guard config.value(for: .isDirectPasteEnabled) || forcesDirectPaste else {
            copyOnly(ids, options: options)
            return
        }
        guard AccessibilityAccess.isGranted else {
            pasteWithoutAccessibility(ids, options: options)
            return
        }
        if services.restorer.restore(ids, options: options) {
            picksController.didPaste(ids)
            Task { SyntheticKeystroke.postPaste() }
        }
        NSApp.deactivate()
    }

    /// Without Accessibility access a paste cannot reach the other app: the user chooses
    /// between granting it — and then nothing is pasted or copied this time — and copying
    /// only, for now or from now on.
    private func pasteWithoutAccessibility(_ ids: [ItemID], options: RestoreOptions) {
        NSApp.activate(ignoringOtherApps: true)
        switch permissions.askToPasteToOtherApps() {
        case .enableAccessibilityAccess:
            NSApp.deactivate()
            guard NSApp.modalWindow == nil else {
                NSApp.activate(ignoringOtherApps: true)
                return
            }
            _ = permissions.requestAccessibilityAccess()
        case .copyToClipboard(let doNotAskAgain):
            if doNotAskAgain {
                services.config.set(false, for: .isDirectPasteEnabled)
            }
            copyOnly(ids, options: options)
        }
    }

    /// "To clipboard" mode: the items go to the pasteboard and the panel closes, without a
    /// keystroke.
    private func copyOnly(_ ids: [ItemID], options: RestoreOptions) {
        guard services.restorer.restore(ids, options: options) else {
            NSSound.beep()
            return
        }
        picksController.didPaste(ids)
        // The notice offers the way out of this mode: clicking it turns direct paste back on.
        let hint = Text("\(AppStrings.enableDirectPaste) \(Image(systemName: "chevron.right"))")
        OSD.show(symbol: "checkmark", title: AppStrings.copied, subtitle: hint) { [config = services.config] in
            config.set(true, for: .isDirectPasteEnabled)
        }
        NSApp.deactivate()
    }

    /// ⌘C in the panel: the selection goes to the pasteboard, a notice confirms it, and the panel
    /// closes. No keystroke is sent.
    private func copy(_ ids: [ItemID], plainText: Bool) {
        guard services.restorer.restore(ids, options: plainText ? .plainText : []) else {
            NSSound.beep()
            return
        }
        OSD.show(symbol: "checkmark", title: AppStrings.copied)
        NSApp.deactivate()
    }
}

/// The app menu exists before what carries out some of its entries — "New Text Item" by the
/// preview coordinator, "Getting Started" by the app coordinator itself; this is the wire.
private final class MenuRequests {
    var createTextItem: (() -> Void)?
    var showGettingStarted: (() -> Void)?
    var showTips: (() -> Void)?
    /// Called before the menu opens a window — Settings, About, the licenses — or an alert: the
    /// panel, which closes as they come forward, must not hand activation back to the previous
    /// application.
    var willShowWindow: (() -> Void)?
}
