import AppKit
import os
import PastoCore
import PastoFoundation
import PastoInput

/// Gives a new installation its welcome content, once: three notes in the history and a pinboard
/// with a welcome note and three links.
///
/// It runs at the end of a first launch's welcome flow, right before the notice cards are seeded,
/// and only into a store without pinboards. It is never done again: not on later launches, not
/// after an update, not after the content is deleted.
public final class WelcomeContentSeeder {
    /// What `seedIfNeeded()` did.
    public enum Outcome: Equatable, Sendable {
        /// The content is in the store.
        case seeded
        /// Not a first launch, or this installation already had the content.
        case notNeeded
        /// The store already had a pinboard, so it is not a new one: nothing was written.
        case storeNotNew
        /// The write failed; a later first launch may try again.
        case failed
    }

    private let config: ConfigStore
    private let writer: StoreWriter
    private let application: FrontmostApplication?
    private let strings: WelcomeContentStrings
    private let log = Log.logger(.app)

    /// The content is credited to Pasto as it is running now, in the language the app is showing.
    public convenience init(config: ConfigStore, writer: StoreWriter) {
        self.init(
            config: config,
            writer: writer,
            application: WorkspaceFrontmostApplication.application(.current, icon: NSApp?.applicationIconImage),
            strings: WelcomeContentStrings()
        )
    }

    init(config: ConfigStore, writer: StoreWriter, application: FrontmostApplication?, strings: WelcomeContentStrings) {
        self.config = config
        self.writer = writer
        self.application = application
        self.strings = strings
    }

    /// To be called on a first launch once the welcome flow has ended — after Quick Start has
    /// settled the activation shortcut, which the first note names — and before the launch is
    /// recorded (`ConfigStore.recordLaunch(of:)`): afterwards it is no longer a first launch and
    /// nothing is done.
    ///
    /// Safe to call again: the content goes in as one transaction, the installation is marked
    /// once it is in, and a store that has a pinboard — the content's own included — gets nothing.
    @discardableResult
    public func seedIfNeeded() async -> Outcome {
        let decision = WelcomeContentDecision(
            lastLaunchedVersion: config.lastLaunchedVersion,
            wasSeeded: config.value(for: .isWelcomeContentSeeded)
        )
        guard decision.shouldSeed else { return .notNeeded }

        let content = WelcomeContentCatalog.content(
            strings: strings,
            activationShortcut: config.shortcut(for: .activationShortcut).map { ShortcutDisplay.string(for: $0) },
            application: application
        )
        do {
            let didSeed = try await writer.perform(author: .maintenance) { try $0.seedWelcomeContent(content) }
            // Marked only now: a launch that dies before the write leaves the next first launch
            // free to try, and one that dies after it finds the pinboard and writes nothing.
            config.set(true, for: .isWelcomeContentSeeded)
            return didSeed ? .seeded : .storeNotNew
        } catch {
            log.error("Could not store the welcome content: \(error)")
            return .failed
        }
    }
}
