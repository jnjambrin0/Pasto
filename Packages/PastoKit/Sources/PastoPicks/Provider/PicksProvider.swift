import AppKit
import Foundation
import Observation
import os
import PastoCore
import PastoFoundation
import PastoPermissions

/// Suggestions — the "intelligent clipboard": which history items the user is likely to paste
/// into the application the panel opened over.
///
/// It classifies what is copied, looks at the destination window when the panel opens, ranks
/// the newest history items when the user asks for suggestions, and learns from every paste.
/// Everything happens on the Mac: ScreenCaptureKit, the on-device language model and three files
/// in Pasto's Application Support folder, none of which holds clipboard content.
///
/// The app creates one, calls `start(captures:)` once, and tells it when the panel shows and
/// closes and what is pasted; the panel drives the rest. Its state is observable.
@MainActor
@Observable
public final class PicksProvider {
    // MARK: Observable state

    /// The toolbar offers the suggestions button.
    public private(set) var isOffered = false
    /// Suggestions are offered but screen recording access is missing.
    public private(set) var isScreenAccessMissing = false
    /// Apple Intelligence is on, whether or not its model has finished downloading.
    public private(set) var isModelEnabled = false
    /// The suggestions, best first; empty while there are none or the mode is off.
    public private(set) var items: [ItemID] = []
    /// A ranking is running.
    public private(set) var isLoading = false

    /// The Mac can run the language model. Decided once, at launch.
    @ObservationIgnored public let isSupported: Bool

    /// Whether Apple Intelligence is on right now, asked of the model, so it can be known before
    /// `start(captures:)`: the welcome's suggestions step runs before capture starts.
    public var isAppleIntelligenceOn: Bool {
        client.availability.isEnabled
    }

    // MARK: Collaborators

    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let reader: RecentItemReader
    @ObservationIgnored private let client: any LanguageModelClient
    @ObservationIgnored private let screen: ScreenContextReader
    @ObservationIgnored private let journal: JSONLinesLog<PasteEvent>
    @ObservationIgnored private let pickLog: JSONLinesLog<PickLogEntry>
    @ObservationIgnored private let classStore: ItemClassStore
    @ObservationIgnored private let classifier: LanguageModelItemClassifier
    @ObservationIgnored private let log = Log.logger(.picks)

    // MARK: Session state

    @ObservationIgnored private var gates: PicksGates
    @ObservationIgnored private var hasPrewarmed = false
    @ObservationIgnored private var observations: [Task<Void, Never>] = []
    @ObservationIgnored private var refreshing: Task<Void, Never>?
    @ObservationIgnored private var screenRead: Task<Void, Never>?
    /// The application the panel last opened over: where a paste goes and where suggestions are
    /// ranked for.
    @ObservationIgnored private var destinationApplication: String?
    /// What the destination window was seen to show, for this opening of the panel.
    @ObservationIgnored private var screenFieldKind: FieldKind?
    /// Where suggestions are for, while the mode is on.
    @ObservationIgnored private var context: DestinationContext?
    /// The context of the suggestions on show.
    @ObservationIgnored private var rankedContext: DestinationContext?
    /// The user has moved over, clicked or typed in the revealed suggestions: they stay put.
    @ObservationIgnored private var isStripTouched = false
    /// The log entry of the suggestions on show, written when the mode ends or one is pasted.
    @ObservationIgnored private var entry: PickLogEntry?
    /// A paste made while the mode was on but before its suggestions were ready.
    @ObservationIgnored private var choiceBeforeEntry: (item: ItemID, source: ChoiceSource)?
    @ObservationIgnored private var randomness = SystemRandomNumberGenerator()

    /// Pasto's folder in Application Support, where the store lives too.
    public static var defaultDirectory: URL {
        AppIdentity.applicationSupportDirectory
    }

    /// - Parameters:
    ///   - reader: Reads the history items suggestions are made of.
    ///   - client: The language model; the system's unless told otherwise.
    ///   - directory: Where the journal and the class store go; the pick log goes in its
    ///     `Diagnostics` subfolder.
    public init(
        config: ConfigStore,
        reader: RecentItemReader,
        client: any LanguageModelClient = SystemLanguageModelClient(),
        directory: URL = PicksProvider.defaultDirectory
    ) {
        self.config = config
        self.reader = reader
        self.client = client
        isSupported = client.availability.isSupported
        screen = ScreenContextReader(client: client)
        journal = JSONLinesLog(
            url: directory.appending(path: "paste-journal.jsonl"),
            limit: .age(PicksMetrics.pasteJournalRetention, date: \.timestamp)
        )
        pickLog = JSONLinesLog(
            url: directory.appending(path: "Diagnostics", directoryHint: .isDirectory).appending(path: "suggestion-log.jsonl"),
            limit: .age(PicksMetrics.pickLogRetention, date: \.openedAt)
        )
        classStore = ItemClassStore(url: directory.appending(path: "item-classes.jsonl"))
        classifier = LanguageModelItemClassifier(store: classStore, client: client)
        gates = PicksGates(isSupported: isSupported, isSettingOn: false, isModelEnabled: false, hasScreenAccess: false)
    }

    isolated deinit {
        observations.forEach { $0.cancel() }
        refreshing?.cancel()
        screenRead?.cancel()
    }

    // MARK: - Lifecycle

    /// Starts following the setting, Apple Intelligence and screen recording access, and
    /// classifying what `captures` reports. Does nothing on a Mac that cannot run the model.
    public func start(captures: AsyncStream<CaptureEvent>) {
        guard isSupported, observations.isEmpty else { return }
        observations = [
            Task { [weak self, config] in
                for await isOn in config.values(for: .isPicksEnabled) {
                    self?.update { $0.isSettingOn = isOn }
                }
            },
            Task { [weak self] in
                // Apple Intelligence can be turned on or off in System Settings: it is looked at
                // again whenever an application becomes active.
                self?.refreshModelAvailability()
                let activations = NSWorkspace.shared.notificationCenter
                    .notifications(named: NSWorkspace.didActivateApplicationNotification)
                    .map { _ in }
                for await _ in activations {
                    self?.refreshModelAvailability()
                }
            },
            Task { [weak self] in
                for await isGranted in ScreenRecordingAccess.states() {
                    self?.update { $0.hasScreenAccess = isGranted }
                }
            },
            Task { [weak self] in
                for await event in captures {
                    guard case .captured(let capture) = event, let self, isOperational else { continue }
                    await Self.classify(capture, reader: reader, store: classStore, classifier: classifier)
                }
            },
        ]
    }

    /// The panel is about to show. Until `panelDidShow(destination:)` names the application the
    /// panel opened over, the frontmost one stands in for it; nothing is looked at yet.
    public func panelWillShow() {
        destinationApplication = SystemDestination.frontmostApplication()
    }

    /// The panel has finished showing over `destination`, the application a paste will go to —
    /// the one focus is handed back to when the panel closes, remembered before Pasto activates.
    /// Its window is looked at now, once per opening, whether or not the user then asks for
    /// suggestions.
    public func panelDidShow(destination: String?) {
        screenRead?.cancel()
        screenFieldKind = nil
        destinationApplication = destination

        guard isOperational, let destination = destinationContext(), !destination.isSecureInput,
              !SystemDestination.isIgnored(destination.appBundleIdentifier, by: config.value(for: .ignoredBundleIdentifiers))
        else { return }
        screenRead = Task { [weak self, screen] in
            let fieldKind = await screen.fieldKind(ofApplication: destination.appBundleIdentifier)
            guard !Task.isCancelled, let self else { return }
            screenFieldKind = fieldKind
            rerankIfTheFieldChanged()
        }
    }

    /// The panel starts closing, before its animation: the look at the destination is abandoned
    /// and the suggestions are reset.
    public func panelWillClose() {
        screenRead?.cancel()
        screenRead = nil
        screenFieldKind = nil
        reset()
    }

    // MARK: - The suggestions mode

    /// The user asked for suggestions: rank them for the destination.
    public func activate() {
        refreshing?.cancel()
        choiceBeforeEntry = nil
        rankedContext = nil
        isStripTouched = false
        context = isOperational ? destinationContext() : nil
        items = []
        // Without screen recording access nothing is ranked: the strip asks for it instead.
        guard let context, ScreenRecordingAccess.isGranted else { return }
        isLoading = true
        refreshing = Task { [weak self] in await self?.rankInitially(context) }
    }

    /// The mode ended: back to nothing, and the log entry of what was shown is written.
    public func reset() {
        refreshing?.cancel()
        refreshing = nil
        context = nil
        rankedContext = nil
        isStripTouched = false
        choiceBeforeEntry = nil
        closeEntry()
        items = []
        isLoading = false
    }

    /// The user moved over, clicked or typed in the revealed suggestions: they are not reordered
    /// any more under the pointer.
    public func stripTouched() {
        isStripTouched = true
    }

    /// Items were chosen for pasting and are on the pasteboard. Every paste is noted, wherever it
    /// was chosen: each item goes into the journal, in order; the log entry records only the
    /// first.
    ///
    /// The destination is the one suggestions were ranked for or, outside the mode, the
    /// frontmost application at the time of the call unless that is Pasto. Called from the panel
    /// before it deactivates, outside the mode that is Pasto itself, so the event has no
    /// destination and teaches only how often the item is pasted; from the Paste Stack, which does
    /// not activate Pasto, it is the application pasted into.
    public func didPaste(_ ids: [ItemID], from source: ChoiceSource) {
        guard isOperational, let item = ids.first else { return }
        let destination = context?.appBundleIdentifier ?? SystemDestination.frontmostApplication()
        let pastes = ids.map { (item: $0, date: Date()) }
        Task { [reader, journal, log] in
            for paste in pastes {
                let sourceApplication = try? await reader.item(paste.item)?.sourceAppBundleIdentifier
                let event = PasteEvent(
                    itemIdentifier: paste.item,
                    sourceAppBundleIdentifier: sourceApplication,
                    destinationAppBundleIdentifier: destination,
                    timestamp: paste.date
                )
                do {
                    try await journal.append(event)
                } catch {
                    log.error("Could not add to the picks journal: \(error)")
                }
            }
        }
        if entry != nil {
            entry?.chosen = item
            entry?.chosenFrom = source
            closeEntry()
        } else if context != nil {
            choiceBeforeEntry = (item, source)
        }
    }

    /// Forgets everything suggestions learnt: the journal, the classes and the log. Called when
    /// the history is erased.
    public func eraseData() async {
        // Not worth writing: the log is about to go.
        entry = nil
        panelWillClose()
        await classifier.cancelAll()
        do { try await journal.erase() } catch { log.error("Could not erase the picks journal: \(error)") }
        do { try await classStore.erase() } catch { log.error("Could not erase the picks classes: \(error)") }
        do { try await pickLog.erase() } catch { log.error("Could not erase the picks log: \(error)") }
    }

    // MARK: - Availability

    /// The per-operation gate, read at the time.
    private var isOperational: Bool {
        isSupported && config.value(for: .isPicksEnabled) && client.availability.isEnabled
    }

    private func refreshModelAvailability() {
        let isEnabled = client.availability.isEnabled
        update { $0.isModelEnabled = isEnabled }
    }

    private func update(_ change: (inout PicksGates) -> Void) {
        var gates = gates
        change(&gates)
        guard gates != self.gates else { return }
        self.gates = gates
        if isModelEnabled != gates.isModelEnabled { isModelEnabled = gates.isModelEnabled }
        if isOffered != gates.isOffered { isOffered = gates.isOffered }
        if isScreenAccessMissing != gates.isScreenAccessMissing { isScreenAccessMissing = gates.isScreenAccessMissing }
        // The model is loaded ahead the first time suggestions are usable.
        if !hasPrewarmed, gates.isOffered, gates.hasScreenAccess {
            hasPrewarmed = true
            client.prewarm()
        }
    }

    /// The application the panel opened over and whether secure input is on; the field is not
    /// known yet.
    private func destinationContext() -> DestinationContext? {
        destinationApplication.map {
            DestinationContext(appBundleIdentifier: $0, isSecureInput: SystemDestination.isSecureInputEnabled)
        }
    }

    // MARK: - Ranking

    private func rankInitially(_ context: DestinationContext) async {
        var context = context
        if !context.isSecureInput {
            context.fieldKind = screenFieldKind ?? ApplicationFieldKinds.fieldKind(ofApplication: context.appBundleIdentifier)
        }
        await rank(for: context, isInitial: true)
        guard !Task.isCancelled else { return }
        rerankIfTheFieldChanged()
        isLoading = false
    }

    /// The destination window was looked at after the suggestions were ranked and shows another
    /// kind of field: rank again, unless the user is already using the suggestions.
    private func rerankIfTheFieldChanged() {
        guard let fieldKind = Self.lateFieldKind(
            rankedContext: rankedContext,
            hasEntry: entry != nil,
            isStripTouched: isStripTouched,
            screenFieldKind: screenFieldKind
        ), var context = rankedContext else { return }
        rankedContext = nil
        context.fieldKind = fieldKind
        refreshing = Task { [weak self] in await self?.rank(for: context, isInitial: false) }
    }

    /// The field kind to rank again with, if the late look at the destination calls for it.
    nonisolated static func lateFieldKind(
        rankedContext: DestinationContext?,
        hasEntry: Bool,
        isStripTouched: Bool,
        screenFieldKind: FieldKind?
    ) -> FieldKind? {
        guard let rankedContext, !rankedContext.isSecureInput, hasEntry, !isStripTouched,
              let screenFieldKind, screenFieldKind != rankedContext.fieldKind
        else { return nil }
        return screenFieldKind
    }

    private func rank(for context: DestinationContext, isInitial: Bool) async {
        // Which app the person pastes into is theirs to know: private, like what they copy.
        log.info("Destination context for \(context.appBundleIdentifier, privacy: .private): secure=\(context.isSecureInput), field=\(context.fieldKind?.rawValue ?? "-", privacy: .public)")
        let events: [PasteEvent]
        do {
            events = try await journal.entries()
        } catch {
            log.error("Could not read the picks history: \(error)")
            events = []
        }
        let candidates = context.isSecureInput
            ? []
            : await Self.candidates(reader: reader, store: classStore)
        let features = CandidateFeatures.features(
            of: candidates,
            history: PasteHistory(journal: events),
            destination: context.appBundleIdentifier
        )
        let shown = PicksRanker.rank(
            features, fieldKind: context.fieldKind, isSecureInput: context.isSecureInput, using: &randomness
        )
        // A late ranking gives way to a user who is already using the suggestions or has pasted
        // one, which closed the entry it would replace.
        guard !Task.isCancelled, isInitial || (!isStripTouched && entry != nil) else { return }

        // The entry it replaces is not written: only the last ranking of an opening is logged.
        let previouslyShown = entry?.shown
        let choice = choiceBeforeEntry
        choiceBeforeEntry = nil
        entry = PickLogEntry(
            openedAt: Date(),
            context: context,
            candidates: features,
            shown: shown,
            chosen: choice?.item,
            chosenFrom: choice?.source
        )
        rankedContext = context
        if isInitial || shown != previouslyShown {
            items = shown
        }
        // Something was pasted while these were being worked out: that was the choice, and the
        // entry is complete.
        if choice != nil { closeEntry() }
    }

    /// The newest history items with their classes; the rules classify, off the main actor,
    /// those that have no class yet. The language model is not asked here.
    @concurrent
    private nonisolated static func candidates(reader: RecentItemReader, store: ItemClassStore) async -> [Candidate] {
        let recent: [RecentItemReader.RecentItem]
        do {
            recent = try await reader.newestHistoryItems(limit: PicksMetrics.candidateLimit)
        } catch {
            Log.logger(.picks).error("Could not read the suggestion candidates: \(error)")
            return []
        }
        var candidates: [Candidate] = []
        for item in recent {
            var itemClass = await store.itemClass(of: item.id)
            if itemClass == nil {
                let text = try? await reader.classifiableText(of: item.id)
                itemClass = await store.setRuleClass(ItemClassRules.itemClass(of: text, type: item.type), for: item.id)
            }
            candidates.append(Candidate(
                id: item.id,
                type: item.type,
                sourceAppBundleIdentifier: item.sourceAppBundleIdentifier,
                itemClass: itemClass ?? .unclassified
            ))
        }
        return candidates
    }

    /// Classifies a captured item, whatever its type, by the rules and, for a text they leave
    /// unclassified, queues it for the language model.
    @concurrent
    private nonisolated static func classify(
        _ capture: PasteboardCapture,
        reader: RecentItemReader,
        store: ItemClassStore,
        classifier: LanguageModelItemClassifier
    ) async {
        let text = try? await reader.classifiableText(of: capture.itemID)
        let ruleClass = ItemClassRules.itemClass(of: text, type: capture.itemType)
        await store.setRuleClass(ruleClass, for: capture.itemID)
        if capture.itemType == .text, ruleClass == .unclassified, let text {
            await classifier.enqueue(capture.itemID, text: text)
        }
    }

    // MARK: - Log

    private func closeEntry() {
        guard let entry else { return }
        self.entry = nil
        Task { [pickLog, log] in
            do {
                try await pickLog.append(entry)
            } catch {
                log.error("Could not write the picks log: \(error)")
            }
        }
    }
}
