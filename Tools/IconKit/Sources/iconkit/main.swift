import CoreGraphics
import Foundation

// iconkit: writes every piece of Pasto's visual identity from the descriptions in this package.
// Output is deterministic: running it twice leaves the working tree unchanged.

let usage = """
    usage: swift run --package-path Tools/IconKit iconkit <command> [--root <repo>] [--before <folder>]

    commands:
      all             everything below except `draft`
      app-icon        Pasto/Assets.xcassets/AppIcon.appiconset (16–1024 px, @1x and @2x)
      icon-composer   Pasto/AppIcon.icon (Icon Composer document, Liquid Glass)
      status-item     Pasto/Assets.xcassets/StatusItemIcon.imageset (18 pt template, @1x and @2x)
      dmg             Config/dmg-background.png and @2x (660 × 400 pt), over Config/dmg-texture.png if present
      export          Design/icon/export (PNG, SVG and favicons for the web)
      previews        docs/design/img (contact sheets; Icon Composer renditions need Xcode's ictool)
      draft <folder>  quick renders of the app icon and a contact sheet, for iterating

    DMG (scripts/release.sh):
      dmg-stage <folder>              background TIFF (1x + 2x) and .VolumeIcon.icns into the image's folder
      dmg-window <volume> [--app N]   writes .DS_Store on the mounted read-write image; flags the volume icon
      dmg-inspect <volume> [--app N] [--preview <png>]
                                      reads .DS_Store back, checks every record, draws a mock-up of the window

    Generated pictures (scripts/import-illustrations.sh):
      import-illustration <png> <folder> <name> [--points WxH] [--crop center|bottom]
                                      checks a 3:2 picture, crops it to 8:5 (full width; `bottom` keeps
                                      the bottom edge), writes @1x, @2x and @3x
      import-texture <png> <output png>
                                      checks the DMG texture and stores it at 1320 × 800

    options:
      --root <repo>       repository root (default: found from this source file)
      --before <folder>   with `previews`: an AppIcon.appiconset folder to compare against
      --app <name>        the application on the DMG (default: Pasto.app)
    """

struct Repository {
    let root: URL

    var assetCatalog: URL { root.appendingPathComponent("Pasto/Assets.xcassets") }
    var appIconSet: URL { assetCatalog.appendingPathComponent("AppIcon.appiconset") }
    var statusImageSet: URL { assetCatalog.appendingPathComponent("StatusItemIcon.imageset") }
    var iconComposerDocument: URL { root.appendingPathComponent("Pasto/AppIcon.icon") }
    var config: URL { root.appendingPathComponent("Config") }
    var export: URL { root.appendingPathComponent("Design/icon/export") }
    var previews: URL { root.appendingPathComponent("docs/design/img") }
    var dmgTexture: URL { config.appendingPathComponent("dmg-texture.png") }
    var dmgBackground: URL { config.appendingPathComponent("dmg-background.png") }
    var dmgBackground2x: URL { config.appendingPathComponent("dmg-background@2x.png") }

    /// The generated texture under the DMG background, when one has been imported.
    func loadDMGTexture() throws -> CGImage? {
        FileManager.default.fileExists(atPath: dmgTexture.path) ? try Output.readPNG(dmgTexture) : nil
    }

    /// Tools/IconKit/Sources/iconkit/main.swift → repository root.
    static func located() -> Repository {
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 { url.deleteLastPathComponent() }
        return Repository(root: url)
    }
}

// MARK: - Commands

/// The macOS app icon set: point size × scale, named the way `iconutil` and Xcode expect.
let appIconSlots: [(points: Int, scale: Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2),
]

func appIconFileName(points: Int, scale: Int) -> String {
    "icon_\(points)x\(points)\(scale == 1 ? "" : "@\(scale)x").png"
}

func renderAppIcon(pixels: Int) -> CGImage {
    Rasterizer.render(IconArt.forPixelSize(pixels).classicScene(), pixels: pixels)
}

func writeJSON(_ object: Any, to url: URL) throws {
    let data = try JSONSerialization.data(withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    try Output.ensureDirectory(url.deletingLastPathComponent())
    try (data + Data("\n".utf8)).write(to: url, options: .atomic)
}

func writeAppIconSet(_ repo: Repository) throws {
    var images: [[String: String]] = []
    for slot in appIconSlots {
        let name = appIconFileName(points: slot.points, scale: slot.scale)
        try Output.writePNG(renderAppIcon(pixels: slot.points * slot.scale), to: repo.appIconSet.appendingPathComponent(name))
        images.append(["filename": name, "idiom": "mac", "scale": "\(slot.scale)x", "size": "\(slot.points)x\(slot.points)"])
    }
    try writeJSON(["images": images, "info": ["author": "xcode", "version": 1]],
                  to: repo.appIconSet.appendingPathComponent("Contents.json"))
    print("app-icon       \(appIconSlots.count) PNGs → \(repo.appIconSet.path)")
}

func writeIconComposer(_ repo: Repository) throws {
    try IconComposer.write(IconArt.full, to: repo.iconComposerDocument)
    print("icon-composer  → \(repo.iconComposerDocument.path)")
}

func writeStatusItem(_ repo: Repository) throws {
    try Output.writePNG(StatusGlyph.render(scale: 1), to: repo.statusImageSet.appendingPathComponent("StatusItemIcon.png"))
    try Output.writePNG(StatusGlyph.render(scale: 2), to: repo.statusImageSet.appendingPathComponent("StatusItemIcon@2x.png"))
    try writeJSON([
        "images": [
            ["filename": "StatusItemIcon.png", "idiom": "mac", "scale": "1x"],
            ["filename": "StatusItemIcon@2x.png", "idiom": "mac", "scale": "2x"],
        ],
        "info": ["author": "xcode", "version": 1],
        "properties": ["template-rendering-intent": "template"],
    ], to: repo.statusImageSet.appendingPathComponent("Contents.json"))
    print("status-item    2 PNGs → \(repo.statusImageSet.path)")
}

func writeDMGBackground(_ repo: Repository) throws {
    let texture = try repo.loadDMGTexture()
    for scale in [1, 2] {
        let image = Output.opaque(DMGBackground.render(scale: scale, texture: texture))
        try Output.writePNG(image, to: scale == 1 ? repo.dmgBackground : repo.dmgBackground2x)
    }
    print("dmg            2 PNGs → \(repo.config.path)\(texture == nil ? "" : " (over dmg-texture.png)")")
}

func stageDMG(_ repo: Repository, folder: URL) throws {
    let background = (try Output.readPNG(repo.dmgBackground), try Output.readPNG(repo.dmgBackground2x))
    guard CGFloat(background.0.width) == DMGBackground.size.width, CGFloat(background.0.height) == DMGBackground.size.height,
          background.1.width == background.0.width * 2, background.1.height == background.0.height * 2
    else { throw IconKitError("Config/dmg-background.png must be 660 × 400 and its @2x 1320 × 800: run `iconkit dmg`") }
    try DMGWindow.stage(folder, background: background)
    print("dmg-stage      \(DMGWindow.backgroundFolder)/\(DMGWindow.backgroundName) and \(DMGWindow.volumeIconName) → \(folder.path)")
}

func inspectDMG(volume: URL, appName: String, preview: URL?) throws {
    let inspection = try DMGWindow.inspect(volume: volume, appName: appName)
    inspection.lines.forEach { print($0) }
    if let preview {
        try Output.writePNG(DMGWindow.preview(volume: volume, inspection: inspection), to: preview)
        print("  mock-up → \(preview.path)")
    }
    if !inspection.problems.isEmpty {
        throw IconKitError("the DMG window is not laid out as it should be: \(inspection.problems.joined(separator: "; "))")
    }
}

func writeExports(_ repo: Repository) throws {
    let full = IconArt.full
    try Output.writePNG(renderAppIcon(pixels: 1024), to: repo.export.appendingPathComponent("pasto-icon-1024.png"))
    try Output.writePNG(renderAppIcon(pixels: 512), to: repo.export.appendingPathComponent("pasto-icon-512.png"))
    try Output.write(SVGWriter().document(full.classicScene()), to: repo.export.appendingPathComponent("pasto-icon.svg"))

    // Favicons fill their square with the tile: no margin, no shadow. The 180 px apple-touch-icon is
    // an opaque square because iOS applies its own mask.
    let favicons: [(pixels: Int, art: IconArt, shape: IconArt.TileShape)] = [
        (32, .small, .flat), (180, full, .square), (512, full, .flat),
    ]
    for favicon in favicons {
        let image = Rasterizer.render(favicon.art.classicScene(shape: favicon.shape), pixelWidth: favicon.pixels,
                                      pixelHeight: favicon.pixels, crop: favicon.art.tileRect)
        try Output.writePNG(image, to: repo.export.appendingPathComponent("favicon-\(favicon.pixels).png"))
    }
    let faviconSVG = SVGWriter(viewBox: full.tileRect, size: CGSize(width: 512, height: 512)).document(full.classicScene(shape: .flat))
    try Output.write(faviconSVG, to: repo.export.appendingPathComponent("favicon.svg"))
    print("export         → \(repo.export.path)")
}

func writePreviews(_ repo: Repository, before: URL?) throws {
    let sizes = [256, 128, 64, 32, 16]
    let after = sizes.map(renderAppIcon(pixels:))
    try Output.writePNG(Sheets.sizeSheet(rows: [after], zoomIndices: [3, 4], zoom: 6),
                        to: repo.previews.appendingPathComponent("icon-sizes.png"))

    if let before {
        let files = ["icon_128x128@2x.png", "icon_128x128.png", "icon_32x32@2x.png", "icon_32x32.png", "icon_16x16.png"]
        let old = try files.map { try Output.readPNG(before.appendingPathComponent($0)) }
        try Output.writePNG(Sheets.sizeSheet(rows: [old, after], zoomIndices: [3, 4], zoom: 6),
                            to: repo.previews.appendingPathComponent("icon-before-after.png"))
    }

    try Output.writePNG(StatusGlyph.sheet(), to: repo.previews.appendingPathComponent("status-item.png"))
    try Output.writePNG(DMGBackground.layoutPreview(icon: renderAppIcon(pixels: 256), texture: try repo.loadDMGTexture()),
                        to: repo.previews.appendingPathComponent("dmg-layout.png"))

    // Icon Composer renditions, rendered by Apple's own renderer from the committed document.
    let temporary = FileManager.default.temporaryDirectory.appendingPathComponent("iconkit-\(ProcessInfo.processInfo.processIdentifier)")
    defer { try? FileManager.default.removeItem(at: temporary) }
    do {
        var renders: [String: CGImage] = [:]
        for rendition in IconComposer.renditions {
            let file = temporary.appendingPathComponent("\(rendition).png")
            try IconComposer.render(repo.iconComposerDocument, rendition: rendition, pixels: 256, to: file)
            renders[rendition] = try Output.readPNG(file)
        }
        let light = Sheets.strip(["Default", "TintedLight", "ClearLight"].compactMap { renders[$0] }, side: 256, background: Sheets.light)
        let dark = Sheets.strip(["Dark", "TintedDark", "ClearDark"].compactMap { renders[$0] }, side: 256, background: Sheets.dark)
        try Output.writePNG(Sheets.stack([light, dark], background: .white),
                            to: repo.previews.appendingPathComponent("icon-composer-renditions.png"))
    } catch {
        print("previews       skipped the Icon Composer renditions: \(error)")
    }
    print("previews       → \(repo.previews.path)")
}

func writeDraft(to folder: URL) throws {
    let sizes = [1024, 256, 128, 64, 32, 16]
    var images: [CGImage] = []
    for size in sizes {
        let image = renderAppIcon(pixels: size)
        images.append(image)
        try Output.writePNG(image, to: folder.appendingPathComponent("icon-\(size).png"))
    }
    try Output.writePNG(Sheets.sizeSheet(rows: [Array(images.dropFirst())], zoomIndices: [3, 4], zoom: 6),
                        to: folder.appendingPathComponent("sheet.png"))
    try Output.writePNG(StatusGlyph.sheet(), to: folder.appendingPathComponent("status-item.png"))
    let texture = try Repository.located().loadDMGTexture()
    try Output.writePNG(DMGBackground.render(scale: 2, texture: texture), to: folder.appendingPathComponent("dmg@2x.png"))
    try Output.writePNG(DMGBackground.layoutPreview(icon: renderAppIcon(pixels: 256), texture: texture),
                        to: folder.appendingPathComponent("dmg-layout.png"))
    print("draft          → \(folder.path)")
}

// MARK: - Entry point

/// "400x250" → 400 × 250.
func parseSize(_ text: String) -> CGSize? {
    let parts = text.lowercased().split(separator: "x").compactMap { Double($0) }
    return parts.count == 2 ? CGSize(width: parts[0], height: parts[1]) : nil
}

/// Splits `--name value` options from the positional arguments.
func parse(_ raw: [String]) -> (positional: [String], options: [String: String]) {
    var positional: [String] = []
    var options: [String: String] = [:]
    var index = 0
    while index < raw.count {
        if raw[index].hasPrefix("--"), index + 1 < raw.count {
            options[raw[index]] = raw[index + 1]
            index += 2
        } else {
            positional.append(raw[index])
            index += 1
        }
    }
    return (positional, options)
}

let (arguments, options) = parse(Array(CommandLine.arguments.dropFirst()))
let repository = options["--root"].map { Repository(root: URL(fileURLWithPath: $0)) } ?? Repository.located()
let before = options["--before"].map { URL(fileURLWithPath: $0) }
let appName = options["--app"] ?? "Pasto.app"

func argument(_ index: Int, _ what: String) throws -> URL {
    guard arguments.count > index else { throw IconKitError("\(arguments[0]) needs \(what)") }
    return URL(fileURLWithPath: arguments[index])
}

do {
    switch arguments.first {
    case "all":
        try writeAppIconSet(repository)
        try writeIconComposer(repository)
        try writeStatusItem(repository)
        try writeDMGBackground(repository)
        try writeExports(repository)
        try writePreviews(repository, before: before)
    case "app-icon": try writeAppIconSet(repository)
    case "icon-composer": try writeIconComposer(repository)
    case "status-item": try writeStatusItem(repository)
    case "dmg": try writeDMGBackground(repository)
    case "export": try writeExports(repository)
    case "previews": try writePreviews(repository, before: before)
    case "draft":
        try writeDraft(to: argument(1, "a folder"))
    case "dmg-stage":
        try stageDMG(repository, folder: argument(1, "the folder that becomes the image"))
    case "dmg-window":
        let volume = try argument(1, "the mounted volume")
        try DMGWindow.write(volume: volume, appName: appName)
        print("dmg-window     .DS_Store and custom icon flag → \(volume.path)")
    case "dmg-inspect":
        try inspectDMG(volume: argument(1, "the mounted volume"), appName: appName,
                       preview: options["--preview"].map { URL(fileURLWithPath: $0) })
    case "import-illustration":
        let input = try argument(1, "a picture"), folder = try argument(2, "an output folder")
        guard arguments.count > 3 else { throw IconKitError("import-illustration needs a name") }
        let points = options["--points"].flatMap(parseSize) ?? CGSize(width: 400, height: 250)
        guard let crop = GeneratedImages.Crop(rawValue: options["--crop"] ?? "center") else {
            throw IconKitError("--crop is center or bottom")
        }
        let image = try GeneratedImages.displayCrop(of: GeneratedImages.load(input), name: input.lastPathComponent, crop: crop)
        try GeneratedImages.writeScales(image, points: points, name: arguments[3], to: folder)
        print("import         \(input.lastPathComponent) → \(folder.path)/\(arguments[3]).png (\(Int(points.width)) × \(Int(points.height)) pt, @1x–@3x)")
    case "import-texture":
        let input = try argument(1, "a picture"), output = try argument(2, "an output file")
        try GeneratedImages.importTexture(input, to: output)
        print("import         \(input.lastPathComponent) → \(output.path)")
    default:
        print(usage)
    }
} catch {
    FileHandle.standardError.write(Data("iconkit: \(error)\n".utf8))
    exit(1)
}
