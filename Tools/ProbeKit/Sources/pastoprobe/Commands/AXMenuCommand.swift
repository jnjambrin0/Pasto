import ProbeCore

enum AXMenuCommand: Command {
    static let name = "ax-menu"
    static let summary = "Dump the menu an app is showing, or its status items (needs Accessibility)."
    static let usage = """
    ax-menu --app <app> [--at x,y] [--max-depth 6] [--outline]     the open context/pop-up menu
           pastoprobe ax-menu --app <app> --extras [--outline]            the app's status items
           --outline prints one indented line per item: title, shortcut, state.
    """
    static let spec = CommandLineArguments.Spec(valueOptions: ["app", "at", "max-depth"], flags: ["extras", "outline"])

    static func run(_ arguments: CommandLineArguments) async throws {
        try arguments.expectPositionals(0)
        let app = try arguments.targetApp()
        let maxDepth = try arguments.nonNegativeInt("max-depth", default: 6)
        let nodes: [AXMenuNode]
        if arguments.flag("extras") {
            nodes = try AXMenuReader.extras(app: app, maxDepth: maxDepth)
        } else {
            let point = try arguments.string("at").map(Geometry.point(parsing:))
            nodes = [try AXMenuReader.openMenu(app: app, at: point, maxDepth: maxDepth)]
        }
        guard arguments.flag("outline") else {
            try Console.json(nodes)
            return
        }
        for node in nodes { outline(node, depth: 0) }
    }

    private static func outline(_ node: AXMenuNode, depth: Int) {
        let indent = String(repeating: "  ", count: depth)
        var line: String
        if node.separator {
            line = "\(indent)---"
        } else {
            line = "\(indent)\(node.role == "AXMenuItem" ? "" : "[\(node.role)] ")\(node.title ?? "")"
            if let shortcut = node.shortcut { line += "  {\(shortcut)}" }
            if let mark = node.mark { line += "  mark=\(mark)" }
            if node.enabled == false { line += "  (disabled)" }
        }
        if let frame = node.frame, depth <= 1 {
            line += "  @\(Int(frame.x)),\(Int(frame.y)) \(Int(frame.w))x\(Int(frame.h))"
        }
        Console.out(line)
        for child in node.children { outline(child, depth: depth + 1) }
    }
}
