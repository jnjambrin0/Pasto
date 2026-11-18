import Foundation

/// Reads the text in an image.
public protocol TextRecognizer: Sendable {
    /// The words found in the encoded image `imageData`, in reading order.
    func recognizeWords(in imageData: Data) async throws -> [String]
}

/// Why an image could not be read at all — as opposed to having no text in it.
public enum TextRecognitionError: Error, Equatable, Sendable {
    case invalidImageData
    case noImageSource
    case noImageProperties
    /// Too few pixels to hold text. Expected for icons and the like: not worth reporting.
    case imageTooSmall
    case imageDecodeFailed
    case thumbnailFailed
}

/// Splits recognized text into words.
public enum RecognizedText {
    /// The words of `text`: what is left between whitespace and punctuation, so that
    /// `me@example.com` is `me`, `example`, `com`.
    public static func words(in text: String) -> [String] {
        text.components(separatedBy: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))
            .filter { !$0.isEmpty }
    }
}
