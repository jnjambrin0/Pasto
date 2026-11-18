import AppKit
import ProbeCore

enum BackdropCommand: Command {
    static let name = "backdrop"
    static let summary = "Cover a strip of the screen (never all of it) with a solid colour for a few seconds, to capture translucent panels over it."
    static let usage = "backdrop --color black|white|gray|#RRGGBB [--rect x,y,w,h] [--screen main|<index>] [--level 3] [--seconds 8]\n"
        + "       Covers --rect (screen points, top-left origin) or, by default, the bottom 400 pt of the screen, where the panel\n"
        + "       appears; never the whole screen, since it hides what the user is doing. It closes itself after --seconds (at most 10)."
    static let spec = CommandLineArguments.Spec(valueOptions: ["color", "screen", "level", "seconds", "rect"])

    private struct Output: Encodable {
        let windowId: Int
        let frame: Frame
        let color: String
        let level: Int
    }

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let color = try parseColor(arguments.requiredString("color"))
        let displayID = try Displays.resolve(arguments.string("screen") ?? "main")
        let level = try arguments.int("level") ?? 3
        // The backdrop hides everything the user is doing: it always takes itself down, and soon.
        let seconds = min(max(try arguments.int("seconds") ?? 8, 1), 10)
        let requested = try arguments.string("rect").map(Frame.init(parsing:))

        let application = NSApplication.shared
        application.setActivationPolicy(.accessory)
        guard let screen = NSScreen.screens.first(where: {
            ($0.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value == displayID
        }) else {
            throw ProbeError.targetNotFound("display \(displayID) has no matching screen")
        }

        // Top-left display coordinates to the screen's bottom-left ones. A full-screen cover is refused.
        let bounds = CGDisplayBounds(displayID)
        let strip = Self.defaultStripHeight
        let covered = requested ?? Frame(x: bounds.minX, y: bounds.maxY - strip, w: bounds.width, h: strip)
        guard covered.w * covered.h < bounds.width * bounds.height * 0.6 else {
            throw ProbeError.usage("the backdrop may cover at most 60 % of the screen; give a smaller --rect")
        }
        let contentRect = NSRect(
            x: screen.frame.minX + (covered.x - bounds.minX),
            y: screen.frame.maxY - (covered.y - bounds.minY) - covered.h,
            width: covered.w, height: covered.h)
        let window = NSWindow(contentRect: contentRect, styleMask: .borderless, backing: .buffered, defer: false)
        window.backgroundColor = NSColor(
            srgbRed: CGFloat(color.r) / 255, green: CGFloat(color.g) / 255, blue: CGFloat(color.b) / 255, alpha: 1
        )
        window.isOpaque = true
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.level = NSWindow.Level(rawValue: level)
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.setFrame(contentRect, display: true)
        window.orderFrontRegardless()

        DispatchQueue.main.asyncAfter(deadline: .now() + .seconds(seconds)) { exit(0) }
        // It can be told to stop sooner; both signals end it cleanly.
        let signals = [SIGINT, SIGTERM].map { number in
            signal(number, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: number, queue: .main)
            source.setEventHandler { exit(0) }
            source.resume()
            return source
        }
        try Console.json(Output(
            windowId: window.windowNumber, frame: covered, color: color.hex, level: level
        ))
        withExtendedLifetime(signals) { application.run() }
    }

    /// Height of the default strip: the main panel at its default height (332 pt) plus margin.
    /// A taller panel (up to 412 pt) needs `--rect`.
    private static let defaultStripHeight = 400.0

    private static func parseColor(_ text: String) throws -> RGBA {
        switch text.lowercased() {
        case "black": return RGBA(r: 0, g: 0, b: 0)
        case "white": return RGBA(r: 255, g: 255, b: 255)
        case "gray", "grey": return RGBA(r: 128, g: 128, b: 128)
        default:
            let digits = text.hasPrefix("#") ? String(text.dropFirst()) : text
            guard digits.count == 6, let value = UInt32(digits, radix: 16) else {
                throw ProbeError.usage("--color expects black, white, gray or #RRGGBB, got '\(text)'")
            }
            return RGBA(r: UInt8(value >> 16 & 0xFF), g: UInt8(value >> 8 & 0xFF), b: UInt8(value & 0xFF))
        }
    }
}
