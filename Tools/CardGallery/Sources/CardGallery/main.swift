import AppKit
import PastoUI

// Renders the sample cards to PNG files. See `GalleryOptions.usage`.

let arguments = Array(CommandLine.arguments.dropFirst())
if arguments.contains("--help") || arguments.contains("-h") {
    print(GalleryOptions.usage)
    exit(0)
}

let options: GalleryOptions
do {
    options = try GalleryOptions(arguments: arguments)
} catch {
    FileHandle.standardError.write(Data("CardGallery: \(error.message)\n\n\(GalleryOptions.usage)\n".utf8))
    exit(1)
}

// An application object is needed for views to draw, but it must never show up or take focus.
NSApplication.shared.setActivationPolicy(.prohibited)

let renderer = CardRenderer(options: options)

// Images are decoded off the main thread and land a moment after a cell is configured. A first
// pass starts every decode; the cards are drawn once they are all in memory.
for sizeClass in options.sizeClasses {
    for sample in SampleCard.all {
        renderer.prepare(sample, sizeClass: sizeClass)
    }
}
try await Task.sleep(for: .milliseconds(500))

var failures = 0
for sizeClass in options.sizeClasses {
    let directory = options.outputDirectory.appendingPathComponent(sizeClass.name, isDirectory: true)
    do {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        for sample in SampleCard.all {
            guard let png = renderer.render(sample, sizeClass: sizeClass) else {
                FileHandle.standardError.write(Data("CardGallery: cannot render \(sample.name)\n".utf8))
                failures += 1
                continue
            }
            let file = directory.appendingPathComponent("\(sample.name).png")
            try png.write(to: file)
            print(file.path)
        }
    } catch {
        FileHandle.standardError.write(Data("CardGallery: \(error.localizedDescription)\n".utf8))
        exit(4)
    }
}
exit(failures == 0 ? 0 : 4)
