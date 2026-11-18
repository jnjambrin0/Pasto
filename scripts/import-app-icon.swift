#!/usr/bin/env swift
// Builds every rendition of the app icon from one full-bleed square artwork.
//
//   swift scripts/import-app-icon.swift [Design/icon/source/app-icon-artwork.png]
//
// The artwork fills its square with no rounded corners. macOS icons are a rounded tile of
// 824 pt in a 1024 pt canvas, with a soft shadow below; smaller sizes are scaled from it.
import AppKit

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let source = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : root.appendingPathComponent("Design/icon/source/app-icon-artwork.png")
guard let artwork = NSImage(contentsOf: source)?.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
    fatalError("Cannot read \(source.path)")
}
precondition(artwork.width == artwork.height && artwork.width >= 1024, "The artwork must be square, 1024 px or larger")

func context(_ size: Int) -> CGContext {
    let c = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                      space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    c.interpolationQuality = .high
    return c
}

/// The tile with its margin and shadow, at 1024 px.
func master() -> CGImage {
    let c = context(1024)
    let tile = CGRect(x: 100, y: 100, width: 824, height: 824)
    // The system's continuous corner, close to a 22.37 % radius.
    let shape = NSBezierPath(roundedRect: tile, xRadius: 185.4, yRadius: 185.4).cgPath
    c.saveGState()
    c.setShadow(offset: CGSize(width: 0, height: -10), blur: 20, color: CGColor(gray: 0, alpha: 0.3))
    c.addPath(shape); c.setFillColor(CGColor(gray: 0, alpha: 1)); c.fillPath()
    c.restoreGState()
    c.addPath(shape); c.clip()
    c.draw(artwork, in: tile)
    return c.makeImage()!
}

func scaled(_ image: CGImage, to size: Int) -> CGImage {
    let c = context(size); c.draw(image, in: CGRect(x: 0, y: 0, width: size, height: size)); return c.makeImage()!
}

func write(_ image: CGImage, _ path: String) {
    let url = root.appendingPathComponent(path)
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try! NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])!.write(to: url)
    print(path)
}

let tile = master()
let set = "Pasto/Assets.xcassets/AppIcon.appiconset"
for (points, scale) in [(16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2), (256, 1), (256, 2), (512, 1), (512, 2)] {
    write(scaled(tile, to: points * scale), "\(set)/icon_\(points)x\(points)\(scale == 2 ? "@2x" : "").png")
}
write(tile, "Design/icon/export/pasto-icon-1024.png")
write(scaled(tile, to: 512), "Design/icon/export/pasto-icon-512.png")
for size in [32, 180, 512] { write(scaled(tile, to: size), "Design/icon/export/favicon-\(size).png") }
