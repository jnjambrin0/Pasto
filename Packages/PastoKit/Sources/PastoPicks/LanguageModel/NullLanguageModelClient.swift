import CoreGraphics

/// The language model of a system that has none: suggestions are not supported.
public struct NullLanguageModelClient: LanguageModelClient {
    public init() {}

    public var availability: LanguageModelAvailability { .unsupported }
    public var acceptsImages: Bool { false }

    public func prewarm() {}

    public func classify(_ text: String) async throws -> ItemClass {
        throw LanguageModelClientError.unavailable
    }

    public func fieldKind(in screenshot: CGImage) async throws -> FieldKind? {
        throw LanguageModelClientError.unavailable
    }
}
