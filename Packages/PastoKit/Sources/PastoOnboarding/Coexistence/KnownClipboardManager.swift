import AppKit
import os
import PastoFoundation
import PastoInput

/// Another clipboard manager Pasto knows about: an app that also keeps what is copied and
/// answers to a system-wide shortcut.
///
/// The list is kept in `Resources/KnownClipboardManagers.json` (shortcuts in the stored format
/// of `Shortcut`: `keyCode` and Cocoa `internalModifiers`). It serves two things only: choosing
/// the initial shortcuts of a new installation, and the notice that another one is open when
/// onboarding ends.
public nonisolated struct KnownClipboardManager: Decodable, Equatable, Sendable {
    /// The app's name, as the notice shows it.
    public let name: String
    public let bundleIdentifiers: [String]
    /// The system-wide shortcuts it uses until its user changes them.
    public let shortcuts: [Shortcut]

    /// The whole list, read once.
    public static let all: [KnownClipboardManager] = load(
        from: Bundle.module.url(forResource: "KnownClipboardManagers", withExtension: "json")
    )

    /// The managers of `list` among the running applications' bundle identifiers, in the
    /// list's order and each once. Identifiers compare without regard to case, as Launch
    /// Services does.
    public static func running(
        among runningBundleIdentifiers: some Sequence<String?>,
        in list: [KnownClipboardManager] = all
    ) -> [KnownClipboardManager] {
        let running = Set(runningBundleIdentifiers.compactMap { $0?.lowercased() })
        return list.filter { manager in
            manager.bundleIdentifiers.contains { running.contains($0.lowercased()) }
        }
    }

    /// The managers open now.
    @MainActor
    public static func running() -> [KnownClipboardManager] {
        running(among: NSWorkspace.shared.runningApplications.map(\.bundleIdentifier))
    }

    /// An unreadable list is an empty one: the checks it feeds then find nothing.
    static func load(from url: URL?) -> [KnownClipboardManager] {
        do {
            guard let url else { throw CocoaError(.fileNoSuchFile) }
            return try JSONDecoder().decode([KnownClipboardManager].self, from: Data(contentsOf: url))
        } catch {
            Log.logger(.app).error("Could not read the list of known clipboard managers: \(error)")
            return []
        }
    }
}
