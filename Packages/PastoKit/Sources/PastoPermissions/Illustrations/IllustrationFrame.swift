import AppKit
import SwiftUI

/// Which art an illustration shows. `automatic` prefers the imported picture and falls back to the
/// vector drawing; the others force one, for comparing them.
package enum IllustrationArtwork: Sendable {
    case automatic
    case vector
}

private struct IllustrationArtworkKey: EnvironmentKey {
    static let defaultValue = IllustrationArtwork.automatic
}

extension EnvironmentValues {
    package var illustrationArtwork: IllustrationArtwork {
        get { self[IllustrationArtworkKey.self] }
        set { self[IllustrationArtworkKey.self] = newValue }
    }
}

/// The pictures imported by `scripts/import-illustrations.sh` (`Resources/Illustrations/`, at @1x,
/// @2x and @3x). Read once per name and kept: they are small and every screen shows one.
@MainActor
package enum IllustrationImages {
    private static var cache: [String: NSImage?] = [:]

    package static func image(named name: String, in bundle: Bundle) -> NSImage? {
        let key = "\(bundle.bundlePath)/\(name)"
        if let cached = cache[key] { return cached }
        let image = load(name, from: bundle)
        cache[key] = image
        return image
    }

    private static func load(_ name: String, from bundle: Bundle) -> NSImage? {
        // The usual case: the resources are flattened into the bundle and AppKit gathers the scales
        // (or Xcode has combined them into one TIFF).
        if let image = bundle.image(forResource: name) { return image }
        // A build that keeps the folder: put the scales together by hand.
        guard let folder = bundle.resourceURL?.appendingPathComponent("Illustrations") else { return nil }
        var image: NSImage?
        for scale in 1...3 {
            let file = folder.appendingPathComponent(scale == 1 ? "\(name).png" : "\(name)@\(scale)x.png")
            guard let data = try? Data(contentsOf: file), let representation = NSBitmapImageRep(data: data) else { continue }
            let size = CGSize(width: CGFloat(representation.pixelsWide) / CGFloat(scale),
                              height: CGFloat(representation.pixelsHigh) / CGFloat(scale))
            representation.size = size
            if image == nil { image = NSImage(size: size) }
            image?.addRepresentation(representation)
        }
        return image
    }
}

/// An illustration as the screens show it: the imported picture when the module has it, the vector
/// drawing otherwise, at 8:5, clipped to a rounded rectangle and outlined by a hairline.
///
/// The pictures only exist in a light version. In dark mode they are framed (the hairline turns
/// lighter) and dimmed a little, so the light card sits in the dark window without glaring. The
/// vector art has its own dark palette.
///
/// The view takes the width it is offered and keeps 8:5; on its own it is 400 × 250 pt.
package struct IllustrationFrame: View {
    package let imageName: String
    package let bundle: Bundle
    package let cornerRadius: CGFloat
    package let vector: (IllustrationPainter) -> Void

    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.illustrationArtwork) private var artwork

    package init(imageName: String, bundle: Bundle, cornerRadius: CGFloat = IllustrationMetrics.cornerRadius,
                 vector: @escaping (IllustrationPainter) -> Void) {
        self.imageName = imageName
        self.bundle = bundle
        self.cornerRadius = cornerRadius
        self.vector = vector
    }

    package var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        art
            .clipShape(shape)
            .overlay {
                if cornerRadius > 0 {
                    shape.strokeBorder(Color.primary.opacity(borderOpacity), lineWidth: IllustrationMetrics.borderWidth)
                }
            }
            .aspectRatio(IllustrationMetrics.aspectRatio, contentMode: .fit)
            .frame(idealWidth: IllustrationMetrics.designSize.width, idealHeight: IllustrationMetrics.designSize.height)
            .accessibilityHidden(true)
    }

    @ViewBuilder private var art: some View {
        if artwork == .automatic, let image = IllustrationImages.image(named: imageName, in: bundle) {
            Color.clear
                .overlay {
                    Image(nsImage: image)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFill()
                }
                .overlay {
                    if colorScheme == .dark {
                        Color.black.opacity(IllustrationMetrics.darkVeilOpacity)
                    }
                }
                .clipped()
        } else {
            IllustrationCanvas(draw: vector)
        }
    }

    private var borderOpacity: Double {
        colorScheme == .dark ? IllustrationMetrics.darkBorderOpacity : IllustrationMetrics.lightBorderOpacity
    }
}
