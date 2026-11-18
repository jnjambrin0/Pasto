import Foundation

/// Turns the application that was in front into the source of an item.
///
/// The source is the application that was frontmost when the pasteboard was read.
/// `org.nspasteboard.source` can veto a capture but does not change the source.
enum SourceApplicationResolver {
    /// - Parameter stored: What the store already has for that bundle identifier.
    /// - Returns: `nil` unless the application has an identifier, a name and an icon: without
    ///   all three it is neither created nor updated.
    static func sourceApplication(
        for application: FrontmostApplication,
        stored: SourceApplication?
    ) -> SourceApplication? {
        guard let bundleIdentifier = application.bundleIdentifier,
              let name = application.name,
              let icon = application.icon,
              let iconData = ApplicationIcon.pngData(of: icon)
        else { return nil }

        // A stored name is only filled in when it is empty.
        let storedName = stored.map(\.name) ?? ""
        var source = SourceApplication(bundleIdentifier: bundleIdentifier, name: storedName.isEmpty ? name : storedName)

        if let stored, stored.iconData == iconData, stored.colorCode != 0 {
            // Same icon, byte for byte: the colour is not computed again.
            source.iconData = stored.iconData
            source.colorCode = stored.colorCode
        } else {
            source.iconData = iconData
            source.colorCode = ApplicationColor.code(for: ApplicationIcon.colorBitmap(of: icon))
        }
        return source
    }
}
