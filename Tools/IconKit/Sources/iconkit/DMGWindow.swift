import AppKit
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The window Finder shows when the DMG opens, written straight into the volume's `.DS_Store`
/// instead of asking Finder to arrange it (which needs Automation access and a visible Finder).
///
/// `scripts/release.sh` calls `dmg-stage` on the folder it turns into the image (background and
/// volume icon), then `dmg-window` on the mounted read-write image, and `dmg-inspect` on the final,
/// compressed one to check the records and draw a mock-up of the window.
enum DMGWindow {
    static let volumeName = "Pasto"
    /// The content area, which the background picture fills exactly.
    static let contentSize = DMGBackground.size
    /// Finder stores the window's frame, title bar included. With the toolbar hidden a Finder
    /// window has a standard title bar: 32 pt on macOS 27 (`NSWindow.frameRect(forContentRect:
    /// styleMask:)` for a titled window), so the frame is 32 pt taller than the background.
    static let titleBarHeight: CGFloat = 32
    /// Top-left corner of the window on screen, in Finder's coordinates.
    static let windowOrigin = CGPoint(x: 200, y: 120)
    static let iconSize = DMGBackground.iconSize
    static let textSize: CGFloat = 13
    static let backgroundFolder = ".background"
    static let backgroundName = "background.tiff"
    static let volumeIconName = ".VolumeIcon.icns"
    static let applicationsName = "Applications"

    // MARK: Stage

    /// Puts the background (both scales in one TIFF, which is how Finder takes a Retina picture) and
    /// the volume icon into the folder that becomes the image.
    static func stage(_ folder: URL, background: (CGImage, CGImage)) throws {
        let backgroundURL = folder.appendingPathComponent(backgroundFolder).appendingPathComponent(backgroundName)
        try Output.ensureDirectory(backgroundURL.deletingLastPathComponent())
        try writeTIFF([background.0, background.1], scales: [1, 2], to: backgroundURL)
        try VolumeIcon.write(to: folder.appendingPathComponent(volumeIconName))
    }

    static func writeTIFF(_ images: [CGImage], scales: [Int], to url: URL) throws {
        guard let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.tiff.identifier as CFString, images.count, nil) else {
            throw IconKitError("could not create \(url.path)")
        }
        for (image, scale) in zip(images, scales) {
            let dpi = 72 * scale
            let properties: [CFString: Any] = [
                kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi,
                kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFCompression: 5],  // LZW
            ]
            CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        }
        guard CGImageDestinationFinalize(destination) else { throw IconKitError("could not write \(url.path)") }
    }

    // MARK: Window

    /// Writes `.DS_Store` on the mounted, writable volume and flags its custom icon.
    static func write(volume: URL, appName: String) throws {
        let background = volume.appendingPathComponent(backgroundFolder).appendingPathComponent(backgroundName)
        for item in [appName, applicationsName, "\(backgroundFolder)/\(backgroundName)", volumeIconName] {
            guard FileManager.default.fileExists(atPath: volume.appendingPathComponent(item).path) else {
                throw IconKitError("\(volume.path) has no \(item)")
            }
        }
        let alias = try FinderAlias.make(file: background, volume: volume)
        let data = try DSStore.encode(records(appName: appName, backgroundAlias: alias.data))
        try data.write(to: volume.appendingPathComponent(".DS_Store"))
        try setCustomIconFlag(on: volume)
    }

    static func records(appName: String, backgroundAlias: Data) throws -> [DSStore.Record] {
        let frame = CGSize(width: contentSize.width, height: contentSize.height + titleBarHeight)
        let browser: [String: Any] = [
            "ContainerShowSidebar": false,
            "PreviewPaneVisibility": false,
            "ShowPathbar": false,
            "ShowSidebar": false,
            "ShowStatusBar": false,
            "ShowTabView": false,
            "ShowToolbar": false,
            "SidebarWidth": 180,
            "WindowBounds": "{{\(Int(windowOrigin.x)), \(Int(windowOrigin.y))}, {\(Int(frame.width)), \(Int(frame.height))}}",
        ]
        let iconView: [String: Any] = [
            "arrangeBy": "none",
            "backgroundColorBlue": 1.0,
            "backgroundColorGreen": 1.0,
            "backgroundColorRed": 1.0,
            "backgroundImageAlias": backgroundAlias,
            "backgroundType": 2,
            "gridOffsetX": 0.0,
            "gridOffsetY": 0.0,
            "gridSpacing": 100.0,
            "iconSize": Double(iconSize),
            "labelOnBottom": true,
            "showIconPreview": true,
            "showItemInfo": false,
            "textSize": Double(textSize),
            "viewOptionsVersion": 1,
        ]
        return [
            DSStore.Record(name: ".", code: "bwsp", value: .blob(try binaryPlist(browser))),
            DSStore.Record(name: ".", code: "icvl", value: .type("icnv")),
            DSStore.Record(name: ".", code: "icvp", value: .blob(try binaryPlist(iconView))),
            DSStore.Record(name: ".", code: "vSrn", value: .long(1)),
            DSStore.Record(name: ".", code: "vstl", value: .type("icnv")),
            DSStore.Record(name: appName, code: "Iloc", value: .blob(iconLocation(DMGBackground.appSlot))),
            DSStore.Record(name: applicationsName, code: "Iloc", value: .blob(iconLocation(DMGBackground.applicationsSlot))),
        ]
    }

    /// An icon's position: the centre of its picture, from the top-left of the content area, then
    /// the four bytes Finder itself writes after it.
    static func iconLocation(_ center: CGPoint) -> Data {
        var data = Data()
        data.appendUInt32(UInt32(center.x))
        data.appendUInt32(UInt32(center.y))
        data.appendUInt32(0xFFFF_FFFF)
        data.appendUInt32(0xFFFF_0000)
        return data
    }

    static func binaryPlist(_ object: [String: Any]) throws -> Data {
        try PropertyListSerialization.data(fromPropertyList: object, format: .binary, options: 0)
    }

    /// Sets "has custom icon" (0x0400) in the Finder flags of the volume's root, which is what makes
    /// Finder use `.VolumeIcon.icns` (what `SetFile -a C` does).
    static func setCustomIconFlag(on volume: URL) throws {
        var info = finderInfo(volume) ?? [UInt8](repeating: 0, count: 32)
        info[8] |= 0x04
        let result = info.withUnsafeBytes { setxattr(volume.path, "com.apple.FinderInfo", $0.baseAddress, 32, 0, 0) }
        guard result == 0 else { throw IconKitError("could not set the custom icon flag on \(volume.path): errno \(errno)") }
    }

    static func finderInfo(_ url: URL) -> [UInt8]? {
        var info = [UInt8](repeating: 0, count: 32)
        let count = info.withUnsafeMutableBytes { getxattr(url.path, "com.apple.FinderInfo", $0.baseAddress, 32, 0, 0) }
        return count == 32 ? info : nil
    }

    // MARK: Inspection

    struct Inspection {
        var lines: [String] = []
        var problems: [String] = []
        var iconCenters: [String: CGPoint] = [:]
        var windowFrame: CGSize = .zero

        mutating func check(_ condition: Bool, _ description: String) {
            lines.append("    \(condition ? "ok  " : "FAIL") \(description)")
            if !condition { problems.append(description) }
        }
    }

    /// Reads the mounted volume's `.DS_Store` back and checks every record against the layout.
    static func inspect(volume: URL, appName: String) throws -> Inspection {
        var report = Inspection()
        let storeURL = volume.appendingPathComponent(".DS_Store")
        let records = try DSStore.decode(Data(contentsOf: storeURL))
        report.lines.append("  \(storeURL.path): \(records.count) records")
        for record in records {
            report.lines.append("    \(record.name.isEmpty ? "''" : record.name) \(record.code) \(record.value)")
        }
        func record(_ name: String, _ code: String) -> DSStore.Value? {
            records.first { $0.name == name && $0.code == code }?.value
        }
        func plist(_ value: DSStore.Value?) -> [String: Any] {
            guard case let .blob(data) = value else { return [:] }
            return (try? PropertyListSerialization.propertyList(from: data, format: nil)) as? [String: Any] ?? [:]
        }

        report.lines.append("  checks:")
        let browser = plist(record(".", "bwsp"))
        let expectedFrame = "{{\(Int(windowOrigin.x)), \(Int(windowOrigin.y))}, {\(Int(contentSize.width)), \(Int(contentSize.height + titleBarHeight))}}"
        report.check(browser["WindowBounds"] as? String == expectedFrame,
                     "window frame \(browser["WindowBounds"] ?? "missing") (expected \(expectedFrame): 660 × 400 content + 32 title bar)")
        for key in ["ShowSidebar", "ContainerShowSidebar", "ShowToolbar", "ShowStatusBar", "ShowPathbar", "ShowTabView"] {
            report.check(browser[key] as? Bool == false, "\(key) is false")
        }
        report.windowFrame = CGSize(width: contentSize.width, height: contentSize.height + titleBarHeight)
        report.check(record(".", "vstl") == .type("icnv") && record(".", "icvl") == .type("icnv"), "icon view (vstl, icvl)")

        let iconView = plist(record(".", "icvp"))
        report.check((iconView["iconSize"] as? Double) == Double(iconSize), "icon size \(iconView["iconSize"] ?? "missing") pt")
        report.check(iconView["arrangeBy"] as? String == "none", "free arrangement")
        report.check((iconView["textSize"] as? Double) == Double(textSize), "label size \(iconView["textSize"] ?? "missing") pt")
        report.check(iconView["backgroundType"] as? Int == 2, "background type: picture")
        if let aliasData = iconView["backgroundImageAlias"] as? Data, let alias = try? FinderAlias(decoding: aliasData) {
            let target = volume.appendingPathComponent(String(alias.posixPath.dropFirst()))
            report.lines.append("    alias: volume \"\(alias.volumeName)\" at \(alias.mountPoint), \(alias.posixPath), node \(alias.fileID) in \(alias.parentID)")
            report.check(alias.volumeName == volumeName && alias.mountPoint == "/Volumes/\(volumeName)", "alias names the volume \(volumeName)")
            report.check(alias.posixPath == "/\(backgroundFolder)/\(backgroundName)", "alias path \(alias.posixPath)")
            let fileID = try? FinderAlias.nodeID(target), parentID = try? FinderAlias.nodeID(target.deletingLastPathComponent())
            report.check(fileID == alias.fileID && parentID == alias.parentID, "alias node IDs match the file on the volume")
            if let date = try? volume.resourceValues(forKeys: [.creationDateKey]).creationDate {
                report.check(FinderAlias.hfsDate(date) == alias.volumeDate, "alias volume date matches the volume")
            }
            report.check(inspectBackground(target, report: &report), "background picture: 660 × 400 pt at 1x and 2x")
        } else {
            report.check(false, "background alias present and readable")
        }

        for name in [appName, applicationsName] {
            guard case let .blob(data) = record(name, "Iloc"), data.count == 16 else {
                report.check(false, "\(name) has a position")
                continue
            }
            let bytes = [UInt8](data)
            let x = bytes[0..<4].reduce(0) { $0 << 8 | Int($1) }, y = bytes[4..<8].reduce(0) { $0 << 8 | Int($1) }
            report.iconCenters[name] = CGPoint(x: x, y: y)
            let expected = name == appName ? DMGBackground.appSlot : DMGBackground.applicationsSlot
            report.check(CGPoint(x: x, y: y) == expected, "\(name) at (\(x), \(y)), its slot's centre")
            report.check(FileManager.default.fileExists(atPath: volume.appendingPathComponent(name).path), "\(name) is on the volume")
        }
        let link = try? FileManager.default.destinationOfSymbolicLink(atPath: volume.appendingPathComponent(applicationsName).path)
        report.check(link == "/Applications", "Applications links to /Applications")

        // Finder writes the labels black in light mode and white in dark mode over the picture, so
        // the picture behind each label has to carry both.
        let backgroundURL = volume.appendingPathComponent(backgroundFolder).appendingPathComponent(backgroundName)
        if let background = NSImage(contentsOf: backgroundURL)?.representations
            .max(by: { $0.pixelsWide < $1.pixelsWide }) as? NSBitmapImageRep, let image = background.cgImage {
            for (name, center) in report.iconCenters.sorted(by: { $0.key < $1.key }) {
                let label = displayName(name)
                let size = NSAttributedString(string: label, attributes: [.font: NSFont.systemFont(ofSize: textSize)]).size()
                let rect = CGRect(x: center.x - size.width / 2, y: center.y + iconSize / 2 + 4, width: size.width, height: size.height)
                let contrast = labelContrast(rect: rect, background: image)
                report.check(contrast.black >= minimumLabelContrast, String(
                    format: "label \"%@\" on luminance %.3f: %.1f:1 in black (light mode), %.1f:1 in white (dark mode)",
                    label, contrast.luminance, contrast.black, contrast.white))
            }
        }

        let volumeName = (try? volume.resourceValues(forKeys: [.volumeNameKey]).volumeName) ?? nil
        report.check(volumeName == Self.volumeName, "volume name \(volumeName ?? "?")")
        let icon = volume.appendingPathComponent(volumeIconName)
        report.check(NSImage(contentsOf: icon)?.representations.isEmpty == false, "\(volumeIconName) is a readable icon")
        report.check(((finderInfo(volume)?[8] ?? 0) & 0x04) != 0, "volume root flagged with a custom icon")
        return report
    }

    private static func inspectBackground(_ url: URL, report: inout Inspection) -> Bool {
        guard let image = NSImage(contentsOf: url) else { return false }
        let reps = image.representations.map { "\($0.pixelsWide)×\($0.pixelsHigh) px as \(Int($0.size.width))×\(Int($0.size.height)) pt" }
        report.lines.append("    background: \(reps.joined(separator: ", "))")
        let pixelWidths = Set(image.representations.map(\.pixelsWide))
        return image.representations.allSatisfy { $0.size == contentSize } && pixelWidths == [Int(contentSize.width), Int(contentSize.width) * 2]
    }

    // MARK: Mock-up

    /// The window as Finder should draw it from the records: background, the icons at their recorded
    /// centres with their labels, in a light and a dark window.
    static func preview(volume: URL, inspection: Inspection) throws -> CGImage {
        let backgroundURL = volume.appendingPathComponent(backgroundFolder).appendingPathComponent(backgroundName)
        guard let background = NSImage(contentsOf: backgroundURL),
              let retina = background.representations.max(by: { $0.pixelsWide < $1.pixelsWide }) as? NSBitmapImageRep,
              let backgroundImage = retina.cgImage
        else { throw IconKitError("cannot read the background at \(backgroundURL.path)") }

        let scale: CGFloat = 2
        let margin: CGFloat = 28
        let frame = inspection.windowFrame
        let panel = CGSize(width: frame.width + 2 * margin, height: frame.height + 2 * margin)
        let width = Int(panel.width * scale), height = Int(panel.height * 2 * scale)
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: width, pixelsHigh: height, bitsPerSample: 8,
                                      samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                      bytesPerRow: 0, bitsPerPixel: 0)!
        bitmap.size = CGSize(width: panel.width, height: panel.height * 2)
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else { throw IconKitError("no drawing context") }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        for (index, dark) in [false, true].enumerated() {
            // AppKit is y-up: the light window on top.
            let origin = CGPoint(x: 0, y: panel.height * CGFloat(1 - index))
            (dark ? NSColor(srgbRed: 0.11, green: 0.12, blue: 0.13, alpha: 1) : NSColor(srgbRed: 0.84, green: 0.87, blue: 0.9, alpha: 1)).setFill()
            NSRect(origin: origin, size: panel).fill()
            let window = NSRect(x: origin.x + margin, y: origin.y + margin, width: frame.width, height: frame.height)
            let shape = NSBezierPath(roundedRect: window, xRadius: 16, yRadius: 16)
            NSGraphicsContext.saveGraphicsState()
            let shadow = NSShadow()
            shadow.shadowBlurRadius = 22
            shadow.shadowOffset = NSSize(width: 0, height: -8)
            shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.6 : 0.28)
            shadow.set()
            (dark ? NSColor(srgbRed: 0.18, green: 0.18, blue: 0.19, alpha: 1) : NSColor(srgbRed: 0.97, green: 0.97, blue: 0.97, alpha: 1)).setFill()
            shape.fill()
            NSGraphicsContext.restoreGraphicsState()

            NSGraphicsContext.saveGraphicsState()
            shape.addClip()
            let content = NSRect(x: window.minX, y: window.minY, width: contentSize.width, height: contentSize.height)
            context.cgContext.draw(backgroundImage, in: content)
            // Title bar: traffic lights and the volume name.
            for (light, color) in [(0, NSColor(srgbRed: 1, green: 0.37, blue: 0.34, alpha: 1)),
                                   (1, NSColor(srgbRed: 1, green: 0.74, blue: 0.18, alpha: 1)),
                                   (2, NSColor(srgbRed: 0.16, green: 0.78, blue: 0.25, alpha: 1))] {
                color.setFill()
                NSBezierPath(ovalIn: NSRect(x: window.minX + 14 + CGFloat(light) * 20, y: window.maxY - titleBarHeight / 2 - 6,
                                            width: 12, height: 12)).fill()
            }
            let titleAttributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 13, weight: .semibold),
                .foregroundColor: dark ? NSColor(white: 0.9, alpha: 1) : NSColor(white: 0.15, alpha: 1),
            ]
            let title = NSAttributedString(string: volumeName, attributes: titleAttributes)
            title.draw(at: NSPoint(x: window.midX - title.size().width / 2, y: window.maxY - titleBarHeight / 2 - title.size().height / 2))

            let labelColor: NSColor = dark ? .white : .black
            for (name, center) in inspection.iconCenters.sorted(by: { $0.key < $1.key }) {
                let item = volume.appendingPathComponent(name)
                let icon = NSWorkspace.shared.icon(forFile: item.path)
                // Content coordinates are y-down from the top-left of the content area.
                let iconRect = NSRect(x: content.minX + center.x - iconSize / 2, y: content.maxY - center.y - iconSize / 2,
                                      width: iconSize, height: iconSize)
                icon.draw(in: iconRect)
                let label = NSAttributedString(string: displayName(name), attributes: [
                    .font: NSFont.systemFont(ofSize: textSize), .foregroundColor: labelColor,
                ])
                let size = label.size()
                let labelOrigin = NSPoint(x: content.minX + center.x - size.width / 2, y: iconRect.minY - 4 - size.height)
                label.draw(at: labelOrigin)
            }
            NSGraphicsContext.restoreGraphicsState()
        }
        NSGraphicsContext.restoreGraphicsState()
        guard let image = bitmap.cgImage else { throw IconKitError("could not read back the mock-up") }
        return image
    }

    /// Finder hides the `.app` extension of applications by default.
    static func displayName(_ name: String) -> String {
        name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Both label colours must reach this contrast with the picture behind them. WCAG asks 4.5:1 of
    /// body text; a mid tone can give both black and white at most about 4.6:1, so the check leaves a
    /// little room for the mean being an average.
    static let minimumLabelContrast = 4.0

    /// Mean luminance of the background behind a label (content points, y-down) and its contrast
    /// with black and with white text, as WCAG computes it.
    static func labelContrast(rect: CGRect, background: CGImage) -> (luminance: Double, black: Double, white: Double) {
        let luminance = DMGBackground.meanLuminance(of: background, in: rect, scale: CGFloat(background.width) / contentSize.width)
        return (luminance, (luminance + 0.05) / 0.05, 1.05 / (luminance + 0.05))
    }
}

/// The DMG volume's own icon: Pasto's icon, drawn from the same vectors at every size.
enum VolumeIcon {
    static func write(to url: URL) throws {
        let fileManager = FileManager.default
        let iconset = fileManager.temporaryDirectory.appendingPathComponent("pasto-volume-\(ProcessInfo.processInfo.processIdentifier).iconset")
        try? fileManager.removeItem(at: iconset)
        try Output.ensureDirectory(iconset)
        defer { try? fileManager.removeItem(at: iconset) }
        for slot in appIconSlots {
            try Output.writePNG(renderAppIcon(pixels: slot.points * slot.scale),
                                to: iconset.appendingPathComponent(appIconFileName(points: slot.points, scale: slot.scale)))
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
        process.arguments = ["-c", "icns", iconset.path, "-o", url.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw IconKitError("iconutil could not make \(url.path)") }
    }
}
