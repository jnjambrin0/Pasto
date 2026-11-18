import PastoFoundation

/// Whether a pasteboard change is captured at all.
///
/// The decision is taken from the pasteboard's types alone, before any data is fetched: content
/// from a password manager is never read, and nothing it promised lazily is requested.
struct CaptureRules: Sendable {
    enum Decision: Equatable, Sendable {
        case capture
        case skip(SkipReason)
    }

    enum SkipReason: Equatable, Sendable {
        /// Nothing is in front, or what is in front has no bundle identifier.
        case undefinedFrontmostApplication
        case ignoredApplication(String)
        /// The content declares, with `org.nspasteboard.source`, that it comes from an ignored application.
        case ignoredSource(String)
        case ignoredType(String)
    }

    /// The one application for which only an exact entry counts, so that ignoring Firefox
    /// (`org.mozilla.firefox`) does not silently ignore its Developer Edition as well.
    private static let exactMatchOnly = "org.mozilla.firefoxdeveloperedition"

    let ignoredBundleIdentifiers: [String]
    let ignoredPasteboardTypes: [String]

    init(ignoredBundleIdentifiers: [String], ignoredPasteboardTypes: [String]) {
        // An empty entry is contained in every string: it would ignore everything.
        self.ignoredBundleIdentifiers = ignoredBundleIdentifiers.filter { !$0.isEmpty }
        self.ignoredPasteboardTypes = ignoredPasteboardTypes.filter { !$0.isEmpty }
    }

    /// The rules as the user has them now.
    init(config: ConfigStore) {
        self.init(
            ignoredBundleIdentifiers: config.value(for: .ignoredBundleIdentifiers),
            ignoredPasteboardTypes: config.value(for: .ignoredPasteboardTypes)
        )
    }

    /// - Parameters:
    ///   - types: The types of every item on the pasteboard, in order.
    ///   - declaredSource: Reads the pasteboard's `org.nspasteboard.source` string; only called
    ///     when that type is present.
    func decision(
        frontmostBundleIdentifier: String?,
        types: [String],
        declaredSource: () -> String?
    ) -> Decision {
        guard let frontmostBundleIdentifier else {
            return .skip(.undefinedFrontmostApplication)
        }
        if isIgnored(bundleIdentifier: frontmostBundleIdentifier) {
            return .skip(.ignoredApplication(frontmostBundleIdentifier))
        }
        for type in types {
            // The marker only vetoes; it does not make its application the item's source.
            if type == PasteboardMarker.source, let source = declaredSource(), isIgnored(bundleIdentifier: source) {
                return .skip(.ignoredSource(source))
            }
            if isIgnored(pasteboardType: type) {
                return .skip(.ignoredType(type))
            }
        }
        return .capture
    }

    /// Case-sensitive.
    func isIgnored(bundleIdentifier: String) -> Bool {
        if bundleIdentifier == Self.exactMatchOnly {
            return ignoredBundleIdentifiers.contains(bundleIdentifier)
        }
        return ignoredBundleIdentifiers.contains { bundleIdentifier.contains($0) }
    }

    /// One ignored type among all the items is enough to drop the whole change. A type matches
    /// an entry when either contains the other.
    func isIgnored(pasteboardType: String) -> Bool {
        guard !pasteboardType.isEmpty else { return false }
        return ignoredPasteboardTypes.contains { pasteboardType.contains($0) || $0.contains(pasteboardType) }
    }
}
