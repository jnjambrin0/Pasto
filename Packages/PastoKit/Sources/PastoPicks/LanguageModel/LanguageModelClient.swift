import CoreGraphics

/// The two questions suggestions ask the on-device language model.
///
/// Everything runs on the device; an implementation never touches the network. Requests are
/// answered one at a time, in the order they were made.
public protocol LanguageModelClient: Sendable {
    /// Read again on every call: the user can turn Apple Intelligence on or off at any time.
    var availability: LanguageModelAvailability { get }
    /// Whether `fieldKind(in:)` can look at an image.
    var acceptsImages: Bool { get }
    /// Loads the model ahead of the first request. Does nothing unless it is available.
    func prewarm()
    /// The category of a copied text; `unclassified` when it is none of those the model knows.
    func classify(_ text: String) async throws -> ItemClass
    /// The kind of field a screenshot of the destination window most likely shows, or `nil`
    /// when it cannot tell.
    func fieldKind(in screenshot: CGImage) async throws -> FieldKind?
}

/// Why the language model gave no answer, besides cancellation.
public enum LanguageModelClientError: Error, Equatable {
    /// The model is not available.
    case unavailable
    /// No answer in time.
    case timedOut
}
