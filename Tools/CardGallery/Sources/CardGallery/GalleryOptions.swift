import AppKit
import PastoUI

/// The command line of the gallery.
nonisolated struct GalleryOptions {
    enum Appearance: String {
        case dark
        case light
    }

    static let usage = """
    usage: CardGallery --out <dir> [--appearance dark|light] [--size-class large|regular|small|compact|all]
                       [--selected] [--unfocused] [--modifiers cmd|shift|cmd+shift]

    Renders every sample card off screen and writes <dir>/<size class>/<sample>.png at 2x.
    No window is shown and the app never becomes active.

      --appearance   system mode to render in (default: dark)
      --size-class   density to render (default: all). Card sides: large 312, regular 240,
                     small 232, compact 152 pt
      --selected     draw the selection ring
      --unfocused    draw the cards as when the strip does not have keyboard focus
      --modifiers    modifier keys to pretend are held, which shows the shortcut indicator
    """

    var outputDirectory: URL
    var appearance = Appearance.dark
    var sizeClasses = SizeClass.allCases
    var isSelected = false
    var isEmphasized = true
    var modifierFlags: NSEvent.ModifierFlags = []

    init(arguments: [String]) throws(UsageError) {
        var outputPath: String?
        var index = 0

        func value(for flag: String) throws(UsageError) -> String {
            index += 1
            guard index < arguments.count else { throw UsageError("\(flag) needs a value") }
            return arguments[index]
        }

        while index < arguments.count {
            let argument = arguments[index]
            switch argument {
            case "--out":
                outputPath = try value(for: argument)
            case "--appearance":
                let name = try value(for: argument)
                guard let appearance = Appearance(rawValue: name) else { throw UsageError("unknown appearance '\(name)'") }
                self.appearance = appearance
            case "--size-class":
                let name = try value(for: argument)
                sizeClasses = try Self.sizeClasses(named: name)
            case "--selected":
                isSelected = true
            case "--unfocused":
                isEmphasized = false
            case "--modifiers":
                modifierFlags = try Self.modifierFlags(named: try value(for: argument))
            default:
                throw UsageError("unknown argument '\(argument)'")
            }
            index += 1
        }

        guard let outputPath else { throw UsageError("--out is required") }
        outputDirectory = URL(fileURLWithPath: outputPath, isDirectory: true)
    }

    private static func sizeClasses(named name: String) throws(UsageError) -> [SizeClass] {
        switch name {
        case "all": SizeClass.allCases
        case "large": [.large]
        case "regular": [.regular]
        case "small": [.small]
        case "compact": [.compact]
        default: throw UsageError("unknown size class '\(name)'")
        }
    }

    private static func modifierFlags(named name: String) throws(UsageError) -> NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        for key in name.split(separator: "+") {
            switch key {
            case "cmd": flags.insert(.command)
            case "shift": flags.insert(.shift)
            case "opt": flags.insert(.option)
            case "ctrl": flags.insert(.control)
            default: throw UsageError("unknown modifier '\(key)'")
            }
        }
        return flags
    }
}

nonisolated struct UsageError: Error {
    let message: String

    init(_ message: String) {
        self.message = message
    }
}

nonisolated extension SizeClass {
    var name: String {
        switch self {
        case .large: "large"
        case .regular: "regular"
        case .small: "small"
        case .compact: "compact"
        }
    }

    /// The side of a card at this density: in panels 412, 340, 332 and 252 pt tall, respectively.
    var cardSide: CGFloat {
        switch self {
        case .large: 312
        case .regular: 240
        case .small: 232
        case .compact: 152
        }
    }
}
