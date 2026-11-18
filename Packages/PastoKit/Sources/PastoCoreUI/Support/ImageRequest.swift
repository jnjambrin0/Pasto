import CoreGraphics
import Foundation

/// The image one view of a cell shows. A small image is decoded on the spot, so the card has it
/// from its first frame; a large one is decoded off the main actor and arrives later. A cell
/// keeps one request per image it shows and cancels them when it is recycled, so a decode that
/// finishes late never lands on another item's card.
final class ImageRequest {
    enum State {
        /// Being decoded; `loaded` or `failed` follows unless the request is cancelled.
        case loading
        case loaded(CGImage)
        /// No data, or data that is not an image.
        case failed
    }

    private var task: Task<Void, Never>?

    /// Whether a decode is still on its way.
    var isPending: Bool { task != nil }

    /// Reports the image through `apply`: the outcome at once if the image is in memory or small
    /// enough to decode now (`ImageDecoder.inlineDecodingByteLimit`), otherwise `loading` now
    /// and the outcome later. Starting a request replaces the previous one.
    func load(
        _ data: Data?,
        maxPixelSize: Int? = nil,
        with decoder: ImageDecoder,
        apply: @escaping (State) -> Void
    ) {
        cancel()
        guard let data else {
            apply(.failed)
            return
        }
        if let image = decoder.cachedImage(for: data, maxPixelSize: maxPixelSize) {
            apply(.loaded(image))
            return
        }
        if data.count <= ImageDecoder.inlineDecodingByteLimit {
            apply(decoder.decodedImage(for: data, maxPixelSize: maxPixelSize).map(State.loaded) ?? .failed)
            return
        }
        apply(.loading)
        task = Task { [weak self] in
            let image = await decoder.image(for: data, maxPixelSize: maxPixelSize)
            guard let self, !Task.isCancelled else { return }
            task = nil
            apply(image.map(State.loaded) ?? .failed)
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

extension ImageRequest.State {
    /// The image, once there is one.
    var image: CGImage? {
        if case .loaded(let image) = self { image } else { nil }
    }
}
