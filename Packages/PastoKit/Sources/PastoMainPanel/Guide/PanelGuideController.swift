import AppKit
import PastoFoundation
import PastoInput
import PastoUI

/// The panel's guide on screen: small glass labels beside the cards, search, the tabs,
/// suggestions and the "…" menu, one at a time, the first times the panel opens; and a line
/// about suggestions the first time they are used.
/// `PanelGuide` decides what shows; this puts it on screen and remembers, mark by mark, what has
/// been seen.
///
/// The labels live inside the panel: they never take the focus or the keys. Anything the user
/// does in the panel — a key, a click — puts the label away; Escape puts it away and goes no
/// further.
///
/// The app tells it when the panel has shown and when it starts closing, and asks for the tips
/// again from Help › Show Tips; the rest it wires itself.
public final class PanelGuideController {
    private let config: ConfigStore
    private let mainView: MainView
    private weak var picks: PicksController?
    private var guide: PanelGuide
    private let markView = CoachMarkView(frame: .zero)
    private lazy var animator = Animator(hostView: mainView)
    private var eventMonitor: Any?
    private var isPanelOpen = false

    public init(config: ConfigStore, mainView: MainView, picks: PicksController?) {
        self.config = config
        self.mainView = mainView
        self.picks = picks
        guide = PanelGuide(seen: Set(PanelGuide.Mark.allCases.filter { config.value(for: .guideMarkSeen($0)) }))
        markView.onPrimary = { [weak self] in self?.primaryAction() }
        markView.onSecondary = { [weak self] in self?.skip() }
        picks?.onTurnOn = { [weak self] in self?.suggestionsDidTurnOn() }
    }

    isolated deinit {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
    }

    // MARK: - What the app reports

    /// The panel has finished showing: the guide goes on where it was.
    public func panelDidShow() {
        isPanelOpen = true
        startMonitoring()
        // On the next turn, once the strip has placed its cards.
        DispatchQueue.main.async { [weak self] in
            guard let self, isPanelOpen else { return }
            show(guide.panelDidOpen(available: available(), at: Date()))
        }
    }

    /// The panel starts closing.
    public func panelWillClose() {
        isPanelOpen = false
        stopMonitoring()
        guide.panelWillClose(at: Date())
        save()
        hide(animated: false)
    }

    /// Help › Show Tips: the tour starts over, now if the panel is open, or the next time it opens.
    public func showTipsAgain() {
        guide.replay()
        save()
        hide(animated: false)
        if isPanelOpen {
            show(guide.panelDidOpen(available: available(), at: Date()))
        }
    }

    // MARK: - The marks

    private func primaryAction() {
        show(guide.next(available: available(), at: Date()))
        save()
    }

    private func skip() {
        guide.skip()
        save()
        hide(animated: true)
    }

    private func suggestionsDidTurnOn() {
        show(guide.suggestionsDidTurnOn(at: Date()))
        save()
    }

    /// The tour steps whose element is on screen. None while a search or suggestions take the
    /// strip: the tour waits.
    private func available() -> Set<PanelGuide.Mark> {
        let toolbar = mainView.toolbar
        guard !toolbar.isSearchActive, picks?.isActive != true else { return [] }
        var marks: Set<PanelGuide.Mark> = [.search, .pinboards, .more]
        if toolbar.showsSuggestionsButton, !toolbar.suggestionsButton.isHidden {
            marks.insert(.suggestions)
        }
        if firstCard() != nil {
            marks.insert(.cards)
        }
        return marks
    }

    private func show(_ mark: PanelGuide.Mark?) {
        guard let mark, let anchor = anchor(for: mark) else {
            hide(animated: true)
            return
        }
        let wasShowing = markView.superview != nil
        markView.configure(content(for: mark))
        if !wasShowing {
            mainView.addSubview(markView)
        }
        let size = markView.fittingContentSize
        let placement = CoachMarkLayout.frame(
            size: size,
            anchor: anchor.rect,
            in: mainView.bounds,
            sides: anchor.sides,
            gap: CoachMarkMetrics.gap,
            margin: CoachMarkMetrics.margin
        )
        animator.cancel(Self.fadeKey)
        animator.cancel(Self.riseKey)
        markView.frame = placement.frame
        markView.layoutSubtreeIfNeeded()
        // Coming in it fades and rises a little; "Reduce Motion" keeps only the fade.
        let rise = placement.side == .below ? CoachMarkMetrics.appearDistance : -CoachMarkMetrics.appearDistance
        let finalOrigin = placement.frame.origin
        animator.animate(
            key: Self.fadeKey, from: wasShowing ? markView.alphaValue : 0, to: 1,
            duration: CoachMarkMetrics.appearDuration, isMotion: false
        ) { [markView] in markView.alphaValue = $0 }
        animator.animate(
            key: Self.riseKey, from: CGPoint(x: finalOrigin.x, y: finalOrigin.y + rise), to: finalOrigin,
            duration: CoachMarkMetrics.appearDuration
        ) { [markView] in markView.setFrameOrigin($0) }
        announce(markView.content)
    }

    private func hide(animated: Bool) {
        guard markView.superview != nil else { return }
        animator.cancel(Self.riseKey)
        guard animated else {
            animator.cancel(Self.fadeKey)
            markView.removeFromSuperview()
            return
        }
        animator.animate(
            key: Self.fadeKey, from: markView.alphaValue, to: 0,
            duration: CoachMarkMetrics.disappearDuration, isMotion: false
        ) { [markView] in markView.alphaValue = $0 } completion: { [markView] finished in
            if finished { markView.removeFromSuperview() }
        }
    }

    private static let fadeKey = "guide.fade"
    private static let riseKey = "guide.rise"

    // MARK: - Where and what

    private struct Anchor {
        let rect: NSRect
        let sides: [CoachMarkLayout.Side]
    }

    private func anchor(for mark: PanelGuide.Mark) -> Anchor? {
        let toolbar = mainView.toolbar
        let element: NSView
        switch mark {
        case .cards:
            guard let card = firstCard() else { return nil }
            return Anchor(rect: mainView.convert(card.bounds, from: card), sides: [.trailing, .leading, .below])
        case .search: element = toolbar.searchBar
        case .pinboards: element = toolbar.tabBar
        case .suggestions, .suggestionsFirstUse: element = toolbar.suggestionsButton
        case .more: element = toolbar.moreButton
        }
        return Anchor(rect: mainView.convert(element.bounds, from: element), sides: [.below])
    }

    /// The first card on screen: the one the cards' mark explains.
    private func firstCard() -> NSView? {
        let cells = mainView.collectionView.visibleCellsByIndex
        guard let index = cells.keys.min(), let cell = cells[index], !cell.isHidden else { return nil }
        return cell
    }

    private func content(for mark: PanelGuide.Mark) -> CoachMarkView.Content {
        let available = available()
        let step = guide.step(of: mark, available: available).map { PanelGuideStrings.step($0.number, of: $0.count) }
        let primary = !mark.isTourStep ? PanelGuideStrings.gotIt
            : guide.isLastStep(mark, available: available) ? PanelGuideStrings.done : PanelGuideStrings.next
        let (title, message) = text(for: mark)
        return CoachMarkView.Content(
            title: title,
            message: message,
            step: mark.isTourStep ? step : nil,
            primaryTitle: primary,
            secondaryTitle: mark.isTourStep && !guide.isLastStep(mark, available: available) ? PanelGuideStrings.skip : nil
        )
    }

    private func text(for mark: PanelGuide.Mark) -> (title: String, message: String) {
        switch mark {
        case .cards:
            let modifiers = ShortcutDisplay.modifierGlyphs(quickPasteModifiers)
            let quickPaste = modifiers.isEmpty ? nil : PanelGuideStrings.cardsQuickPaste("\(modifiers)1–9")
            return (PanelGuideStrings.cardsTitle, sentences(PanelGuideStrings.cardsMessage, quickPaste))
        case .search:
            return (PanelGuideStrings.searchTitle, PanelGuideStrings.searchMessage)
        case .pinboards:
            let tabBar = mainView.toolbar.tabBar
            var navigation: String?
            if let previous = tabBar.previousPinboardShortcut, let next = tabBar.nextPinboardShortcut {
                navigation = PanelGuideStrings.pinboardsNavigation(
                    previous: ShortcutDisplay.string(for: previous), next: ShortcutDisplay.string(for: next)
                )
            }
            return (PanelGuideStrings.pinboardsTitle, sentences(PanelGuideStrings.pinboardsMessage, navigation))
        case .suggestions:
            return (PanelGuideStrings.suggestionsTitle, PanelGuideStrings.suggestionsMessage)
        case .suggestionsFirstUse:
            return (PanelGuideStrings.suggestionsTitle, PanelGuideStrings.suggestionsFirstUseMessage)
        case .more:
            let activation = config.shortcut(for: .activationShortcut).map { PanelGuideStrings.moreActivation(ShortcutDisplay.string(for: $0)) }
            let stack = config.shortcut(for: .pasteStackShortcut).map { PanelGuideStrings.moreStack(ShortcutDisplay.string(for: $0)) }
            return (PanelGuideStrings.moreTitle, sentences(PanelGuideStrings.moreMessage, activation, stack))
        }
    }

    private func sentences(_ parts: String?...) -> String {
        parts.compactMap(\.self).joined(separator: " ")
    }

    private var quickPasteModifiers: NSEvent.ModifierFlags {
        NSEvent.ModifierFlags(rawValue: UInt(config.value(for: .quickPasteModifierFlags)))
    }

    /// VoiceOver reads the mark as it comes, and can move to its buttons.
    private func announce(_ content: CoachMarkView.Content?) {
        guard let content, NSWorkspace.shared.isVoiceOverEnabled else { return }
        NSAccessibility.post(
            element: NSApp as Any,
            notification: .announcementRequested,
            userInfo: [
                .announcement: "\(content.title). \(content.message)",
                .priority: NSAccessibilityPriorityLevel.high.rawValue,
            ]
        )
        NSAccessibility.post(element: markView, notification: .layoutChanged, userInfo: [.uiElements: [markView]])
    }

    // MARK: - What the user does

    private func startMonitoring() {
        guard eventMonitor == nil else { return }
        eventMonitor = NSEvent.addLocalMonitorForEvents(
            matching: [.keyDown, .leftMouseDown, .rightMouseDown, .otherMouseDown]
        ) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    private func stopMonitoring() {
        if let eventMonitor { NSEvent.removeMonitor(eventMonitor) }
        eventMonitor = nil
    }

    /// Returns true when the event was the guide's: Escape with a mark on screen.
    private func handle(_ event: NSEvent) -> Bool {
        guard isPanelOpen, let window = mainView.window, event.window === window else { return false }
        let isShowing = markView.superview != nil
        if event.type == .keyDown {
            if isShowing, event.keyCode == KeyCode.escape {
                guide.userDidSomething(learnt: [])
                save()
                hide(animated: true)
                return true
            }
            didSomething(learnt: learnt(byKey: event))
        } else {
            // The mark's own buttons answer their clicks.
            if isShowing, markView.bounds.contains(markView.convert(event.locationInWindow, from: nil)) {
                return false
            }
            didSomething(learnt: learnt(byClickAt: event.locationInWindow, in: window))
        }
        return false
    }

    private func didSomething(learnt: Set<PanelGuide.Mark>) {
        let before = guide
        guide.userDidSomething(learnt: learnt)
        guard guide != before else { return }
        save()
        hide(animated: true)
    }

    private func learnt(byKey event: NSEvent) -> Set<PanelGuide.Mark> {
        let tabBar = mainView.toolbar.tabBar
        let tabShortcuts = [tabBar.previousPinboardShortcut, tabBar.nextPinboardShortcut].compactMap(\.self)
            .map { (keyCode: $0.keyCode, modifiers: $0.modifiers) }
        return PanelGuide.learnt(
            byKey: event.keyCode,
            modifiers: event.modifierFlags,
            characters: event.charactersIgnoringModifiers,
            quickPasteModifiers: quickPasteModifiers,
            tabShortcuts: tabShortcuts
        )
    }

    private func learnt(byClickAt point: NSPoint, in window: NSWindow) -> Set<PanelGuide.Mark> {
        guard let view = window.contentView?.hitTest(point) else { return [] }
        let toolbar = mainView.toolbar
        if view.isDescendant(of: toolbar.searchBar) { return [.search] }
        if view.isDescendant(of: toolbar.tabBar) || view.isDescendant(of: toolbar.createPinboardButton) { return [.pinboards] }
        if view.isDescendant(of: toolbar.suggestionsButton) { return [.suggestions] }
        if view.isDescendant(of: toolbar.moreButton) { return [.more] }
        return []
    }

    // MARK: - Memory

    private func save() {
        for mark in PanelGuide.Mark.allCases {
            let isSeen = guide.seen.contains(mark)
            if config.value(for: .guideMarkSeen(mark)) != isSeen {
                config.set(isSeen, for: .guideMarkSeen(mark))
            }
        }
    }
}

private extension ConfigKey where Value == Bool {
    /// One setting per mark of the guide: true once it has been seen.
    static func guideMarkSeen(_ mark: PanelGuide.Mark) -> ConfigKey<Bool> {
        ConfigKey("guide.seen.\(mark.rawValue)", default: false)
    }
}
