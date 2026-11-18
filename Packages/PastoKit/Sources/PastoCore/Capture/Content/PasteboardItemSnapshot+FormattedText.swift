import AppKit

extension PasteboardItemSnapshot {
    /// The item's formatted text, from the first representation that can be read: flat RTFD,
    /// RTFD, RTF. `nil` for an item that carries none of them; HTML does not count.
    public var formattedText: NSAttributedString? {
        RichText.attributedString(of: self)
    }
}
