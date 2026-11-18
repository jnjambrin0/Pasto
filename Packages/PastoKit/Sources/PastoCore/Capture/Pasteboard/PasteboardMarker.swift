import Foundation

/// Pasteboard types Pasto adds to what it writes.
public enum PasteboardMarker {
    /// Zero-length marker identifying content Pasto itself put on the pasteboard.
    public static let ownWrite = "jnjambrino.Pasto"
    /// nspasteboard.org convention: the bundle identifier of the application the content came from.
    public static let source = "org.nspasteboard.source"
}
