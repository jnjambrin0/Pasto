import Foundation

/// One accessibility element, as written by `ax-dump` and read back by `ax-diff`.
public struct AXNode: Codable, Sendable, Equatable {
    public var role: String
    public var subrole: String?
    public var roleDescription: String?
    public var identifier: String?
    public var title: String?
    public var description: String?
    public var value: String?
    /// Screen points, top-left origin.
    public var frame: Frame?
    public var enabled: Bool?
    public var focused: Bool?
    public var selected: Bool?
    public var children: [AXNode]

    public init(
        role: String,
        subrole: String? = nil,
        roleDescription: String? = nil,
        identifier: String? = nil,
        title: String? = nil,
        description: String? = nil,
        value: String? = nil,
        frame: Frame? = nil,
        enabled: Bool? = nil,
        focused: Bool? = nil,
        selected: Bool? = nil,
        children: [AXNode] = []
    ) {
        self.role = role
        self.subrole = subrole
        self.roleDescription = roleDescription
        self.identifier = identifier
        self.title = title
        self.description = description
        self.value = value
        self.frame = frame
        self.enabled = enabled
        self.focused = focused
        self.selected = selected
        self.children = children
    }

    /// Number of nodes in this subtree, the node itself included.
    public var subtreeSize: Int {
        children.reduce(1) { $0 + $1.subtreeSize }
    }
}

/// The document `ax-dump` prints: the application node with its windows as children.
public struct AXDump: Codable, Sendable {
    public var app: TargetApp
    public var capturedAt: String
    /// Where the windows came from: `windows-attribute`, `position-probe` or both joined by `+`.
    public var windowSource: String
    public var nodeCount: Int
    /// True when `--max-depth` or `--max-nodes` cut the walk short.
    public var truncated: Bool
    public var root: AXNode

    public init(app: TargetApp, capturedAt: String, windowSource: String, nodeCount: Int, truncated: Bool, root: AXNode) {
        self.app = app
        self.capturedAt = capturedAt
        self.windowSource = windowSource
        self.nodeCount = nodeCount
        self.truncated = truncated
        self.root = root
    }
}
