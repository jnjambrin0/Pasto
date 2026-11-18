/// The pasteboard type identifiers capture knows by name.
enum PasteboardType {
    static let fileURL = "public.file-url"
    static let url = "public.url"
    static let urlName = "public.url-name"

    static let plainText = "public.plain-text"
    static let utf8PlainText = "public.utf8-plain-text"
    static let utf16PlainText = "public.utf16-plain-text"
    static let text = "public.text"

    static let rtf = "public.rtf"
    static let rtfd = "com.apple.rtfd"
    static let flatRTFD = "com.apple.flat-rtfd"

    static let png = "public.png"
    static let jpeg = "public.jpeg"
    static let heic = "public.heic"
    static let tiff = "public.tiff"
    static let icns = "com.apple.icns"

    /// Present when the content arrived from another device through Universal Clipboard.
    static let remoteClipboard = "com.apple.is-remote-clipboard"
}
