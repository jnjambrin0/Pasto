import AppKit

/// What the cells of a strip share and cannot get from an item's model: services and the user's
/// settings.
///
/// The collection builds one and passes it on every `ItemCell.configure(with:sizeClass:environment:)`;
/// when a setting changes it reconfigures the visible cells.
public struct ItemCellEnvironment {
    public var imageDecoder: ImageDecoder
    /// Held to show the number of the cards quick paste can reach.
    public var quickPasteModifierFlags: NSEvent.ModifierFlags
    /// Held to paste as plain text; the cards show a glyph while it is down.
    public var plainTextModifierFlags: NSEvent.ModifierFlags
    /// When off, link cards show only the title and the full URL.
    public var isLinkPreviewsEnabled: Bool
    /// The clock relative dates are computed against.
    public var now: () -> Date
    /// The modifier keys held right now.
    public var currentModifierFlags: () -> NSEvent.ModifierFlags

    public init(
        imageDecoder: ImageDecoder,
        quickPasteModifierFlags: NSEvent.ModifierFlags = .command,
        plainTextModifierFlags: NSEvent.ModifierFlags = .shift,
        isLinkPreviewsEnabled: Bool = true,
        now: @escaping () -> Date = Date.init,
        currentModifierFlags: @escaping () -> NSEvent.ModifierFlags = { NSEvent.modifierFlags }
    ) {
        self.imageDecoder = imageDecoder
        self.quickPasteModifierFlags = quickPasteModifierFlags
        self.plainTextModifierFlags = plainTextModifierFlags
        self.isLinkPreviewsEnabled = isLinkPreviewsEnabled
        self.now = now
        self.currentModifierFlags = currentModifierFlags
    }
}
