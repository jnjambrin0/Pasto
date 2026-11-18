import CoreGraphics
import Foundation

/// Writes the icon as an Icon Composer document (`AppIcon.icon`): a folder with `icon.json` and the
/// layer artwork in `Assets/`. Xcode 26+ compiles it with `actool` into the Liquid Glass icon, and
/// the system derives the dark, tinted and clear appearances from it.
///
/// The format is not formally documented; what is written here was checked against the files Icon
/// Composer itself produces (Xcode's file template, the Sparkle project's icon) and rendered with
/// `ictool`, the command-line renderer inside Icon Composer.app:
///
/// - the canvas is the icon's square, 1024 × 1024, without the classic 100-unit margin: the system
///   masks it to its own shape and adds the shadow;
/// - `groups` and the `layers` inside each group are listed top-most first;
/// - the background is the document `fill`, not a layer, so the system can swap it for the tinted and
///   clear appearances; per-appearance values go in `<property>-specializations`, an array of
///   `{ "value": … }` (the default) and `{ "appearance": "dark" | "tinted", "value": … }`.
enum IconComposer {
    struct Group {
        /// Layer names as `IconArt.contentLayers` produces them, top-most first, and whether the
        /// system renders each one as Liquid Glass.
        var layers: [(name: String, glass: Bool)]
        var shadowOpacity: Double
        var specular: Bool
        var translucency: Double?
    }

    /// Top-most first. Only the cards are glass: it gives them the bright bevelled edge the classic
    /// icon draws by hand. Glass text lines look like raised chips, and glass grass loses its colour.
    static let groups = [
        Group(layers: [("grass-near", false), ("grass-middle", false)], shadowOpacity: 0.35, specular: false),
        Group(layers: [("card-text", false), ("card-front", true), ("cards-back", true)], shadowOpacity: 0.5, specular: true),
        Group(layers: [("grass-far", false)], shadowOpacity: 0, specular: false),
    ]

    static func write(_ art: IconArt, to document: URL) throws {
        let assets = document.appendingPathComponent("Assets")
        // Start from an empty folder so renamed layers never leave stale files behind.
        if FileManager.default.fileExists(atPath: assets.path) {
            try FileManager.default.removeItem(at: assets)
        }
        try Output.ensureDirectory(assets)

        let layers = Dictionary(uniqueKeysWithValues: art.contentLayers(withShadows: false).map { ($0.name, $0) })
        // The document's square is the tile; the classic grid maps onto it through the view box.
        let writer = SVGWriter(includeShadows: false, viewBox: art.tileRect, size: CGSize(width: 1024, height: 1024))
        var groupObjects: [[String: Any]] = []
        for group in groups {
            var layerObjects: [[String: Any]] = []
            for (name, glass) in group.layers {
                guard let layer = layers[name] else { throw IconKitError("No layer named \(name)") }
                let file = "\(name).svg"
                try Output.write(writer.document(Scene(side: Grid.canvas, layers: [layer])), to: assets.appendingPathComponent(file))
                layerObjects.append(["image-name": file, "name": name, "glass": glass])
            }
            var object: [String: Any] = [
                "layers": layerObjects,
                "specular": group.specular,
            ]
            if group.shadowOpacity > 0 {
                object["shadow"] = ["kind": "neutral", "opacity": decimal(group.shadowOpacity)]
            } else {
                object["shadow"] = ["kind": "none", "opacity": 0]
            }
            if let translucency = group.translucency {
                object["translucency"] = ["enabled": true, "value": decimal(translucency)]
            }
            groupObjects.append(object)
        }

        let root: [String: Any] = [
            "fill-specializations": [
                ["value": gradient(Palette.tileTop, Palette.tileBottom)],
                ["appearance": "dark", "value": gradient(Palette.darkTileTop, Palette.darkTileBottom)],
            ],
            "groups": groupObjects,
            "supported-platforms": ["squares": ["macOS"]],
        ]
        let json = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        try json.write(to: document.appendingPathComponent("icon.json"), options: .atomic)
    }

    /// A top-to-bottom gradient, tilted like the classic tile's.
    private static func gradient(_ top: RGBA, _ bottom: RGBA) -> [String: Any] {
        [
            "linear-gradient": [top.iconComposerString, bottom.iconComposerString],
            "orientation": ["start": ["x": decimal(0.32), "y": 0], "stop": ["x": decimal(0.68), "y": 1]],
        ]
    }

    /// JSONSerialization writes binary doubles with all their digits (0.4 → 0.40000000000000002);
    /// a decimal number keeps the file readable.
    static func decimal(_ value: Double) -> NSDecimalNumber {
        NSDecimalNumber(string: number(CGFloat(value), digits: 3))
    }

    /// Renders the document with `ictool` (inside Icon Composer.app), if it is installed.
    static func render(_ document: URL, rendition: String, pixels: Int, to output: URL) throws {
        let tool = URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Applications/Icon Composer.app/Contents/Executables/ictool")
        guard FileManager.default.isExecutableFile(atPath: tool.path) else {
            throw IconKitError("ictool not found at \(tool.path)")
        }
        try Output.ensureDirectory(output.deletingLastPathComponent())
        let process = Process()
        process.executableURL = tool
        process.arguments = [document.path, "--export-image", "--output-file", output.path, "--platform", "macOS",
                             "--rendition", rendition, "--width", "\(pixels)", "--height", "\(pixels)", "--scale", "1"]
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0, FileManager.default.fileExists(atPath: output.path) else {
            throw IconKitError("ictool could not render \(rendition)")
        }
    }

    static let renditions = ["Default", "Dark", "TintedLight", "TintedDark", "ClearLight", "ClearDark"]
}
