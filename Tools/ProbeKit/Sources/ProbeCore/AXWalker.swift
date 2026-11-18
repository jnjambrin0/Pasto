import AppKit
import ApplicationServices

/// Reads an app's accessibility tree into `AXNode` values.
@MainActor
public enum AXWalker {
    public struct Options: Sendable {
        public var maxDepth = 64
        public var maxNodes = 20_000
        public var includeValues = true
        /// Restricts the dump to one of the discovered windows.
        public var windowIndex: Int?

        public init() {}
    }

    /// Longest string kept for any text attribute.
    public static let maxStringLength = 120

    public static func dump(app: TargetApp, options: Options) throws -> AXDump {
        try Permissions.requireAccessibility()
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 2)

        var (windows, source) = try discoverWindows(of: application)
        guard !windows.isEmpty else {
            throw ProbeError.targetNotFound(
                "\(app.name ?? "pid \(app.pid)") exposes no accessibility windows (is the panel visible?)"
            )
        }
        if let index = options.windowIndex {
            guard windows.indices.contains(index) else {
                throw ProbeError.targetNotFound("window index \(index) is out of range (\(windows.count) windows found)")
            }
            windows = [windows[index]]
        }

        var walk = Walk(options: options)
        var root = walk.read(application).node
        walk.nodeCount += 1
        for window in windows {
            guard walk.nodeCount < options.maxNodes else {
                walk.truncated = true
                break
            }
            root.children.append(walk.subtree(window, depth: 1))
        }
        return AXDump(
            app: app,
            capturedAt: ProbeClock.isoNow(),
            windowSource: source,
            nodeCount: walk.nodeCount,
            truncated: walk.truncated,
            root: root
        )
    }

    // MARK: Window discovery

    /// `kAXWindowsAttribute` first, then whatever the app answers when hit-tested along the bottom
    /// of the main screen. The second pass finds non-activating panels that the windows list omits.
    private static func discoverWindows(of application: AXUIElement) throws -> (windows: [AXUIElement], source: String) {
        var value: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(application, kAXWindowsAttribute as CFString, &value)
        if status == .apiDisabled {
            throw ProbeError.permission("the accessibility API is disabled for this process")
        }
        var windows = elements(in: value)
        var sources = windows.isEmpty ? [] : ["windows-attribute"]

        var probed = false
        for hit in probeBottomOfMainScreen(application) {
            // An app with nothing under the point answers with its menu bar; that is not a window.
            guard let window = containingWindow(of: hit, application: application),
                  string(window, kAXRoleAttribute) != kAXMenuBarRole,
                  !windows.contains(where: { CFEqual($0, window) })
            else { continue }
            windows.append(window)
            probed = true
        }
        if probed { sources.append("position-probe") }
        return (windows, sources.joined(separator: "+"))
    }

    private static func probeBottomOfMainScreen(_ application: AXUIElement) -> [AXUIElement] {
        let screen = CGDisplayBounds(CGMainDisplayID())
        var hits: [AXUIElement] = []
        for inset in [24.0, 120.0, 240.0] {
            for fraction in [0.1, 0.3, 0.5, 0.7, 0.9] {
                var hit: AXUIElement?
                let x = Float(screen.minX + screen.width * fraction)
                let y = Float(screen.maxY - inset)
                if AXUIElementCopyElementAtPosition(application, x, y, &hit) == .success, let hit,
                   !CFEqual(hit, application) {
                    hits.append(hit)
                }
            }
        }
        return hits
    }

    private static func containingWindow(of element: AXUIElement, application: AXUIElement) -> AXUIElement? {
        if string(element, kAXRoleAttribute) == kAXWindowRole { return element }
        if let window = elements(in: copy(element, kAXWindowAttribute)).first { return window }
        // No window attribute: climb to the ancestor that sits directly under the application.
        var current = element
        for _ in 0..<64 {
            guard let parent = elements(in: copy(current, kAXParentAttribute)).first else { return current }
            if CFEqual(parent, application) { return current }
            current = parent
        }
        return nil
    }

    // MARK: Attribute helpers

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    /// Accepts either a single element or an array of them.
    fileprivate static func elements(in value: CFTypeRef?) -> [AXUIElement] {
        guard let value else { return [] }
        let candidates = (value as? [AnyObject]) ?? [value]
        return candidates.compactMap { candidate in
            CFGetTypeID(candidate) == AXUIElementGetTypeID() ? unsafeDowncast(candidate, to: AXUIElement.self) : nil
        }
    }

    // MARK: Tree walk

    @MainActor
    private struct Walk {
        let options: Options
        var nodeCount = 0
        var truncated = false

        private static let attributes: [String] = [
            kAXRoleAttribute, kAXSubroleAttribute, kAXRoleDescriptionAttribute, kAXIdentifierAttribute,
            kAXTitleAttribute, kAXDescriptionAttribute, kAXValueAttribute, kAXPositionAttribute,
            kAXSizeAttribute, kAXEnabledAttribute, kAXFocusedAttribute, kAXSelectedAttribute,
            kAXChildrenAttribute,
        ]

        mutating func subtree(_ element: AXUIElement, depth: Int) -> AXNode {
            nodeCount += 1
            var (node, children) = read(element)
            guard !children.isEmpty else { return node }
            guard depth < options.maxDepth else {
                truncated = true
                return node
            }
            for child in children {
                guard nodeCount < options.maxNodes else {
                    truncated = true
                    break
                }
                node.children.append(subtree(child, depth: depth + 1))
            }
            return node
        }

        /// One round trip to the target app per element.
        func read(_ element: AXUIElement) -> (node: AXNode, children: [AXUIElement]) {
            var raw: CFArray?
            let status = AXUIElementCopyMultipleAttributeValues(
                element, Self.attributes as CFArray, AXCopyMultipleAttributeOptions(rawValue: 0), &raw
            )
            // Attributes the element lacks come back as AXValue error placeholders, which every
            // conversion below rejects by type.
            guard status == .success, let values = raw as? [AnyObject], values.count == Self.attributes.count else {
                return (AXNode(role: "AXUnknown"), [])
            }
            let node = AXNode(
                role: text(values[0]) ?? "AXUnknown",
                subrole: text(values[1]),
                roleDescription: text(values[2]),
                identifier: text(values[3]),
                title: text(values[4]),
                description: text(values[5]),
                value: options.includeValues ? valueText(values[6]) : nil,
                frame: frame(position: values[7], size: values[8]),
                enabled: values[9] as? Bool,
                focused: values[10] as? Bool,
                selected: values[11] as? Bool
            )
            return (node, AXWalker.elements(in: values[12]))
        }

        private func text(_ object: AnyObject) -> String? {
            guard let string = object as? String, !string.isEmpty else { return nil }
            guard string.count > AXWalker.maxStringLength else { return string }
            return string.prefix(AXWalker.maxStringLength) + "…"
        }

        /// Values are strings for text and numbers for sliders, checkboxes and the like.
        private func valueText(_ object: AnyObject) -> String? {
            text(object) ?? (object as? NSNumber)?.stringValue
        }

        private func frame(position: AnyObject, size: AnyObject) -> Frame? {
            var origin = CGPoint.zero
            var extent = CGSize.zero
            guard CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
                  AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
                  AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
            else { return nil }
            // Some SwiftUI elements report NaN or infinite geometry; JSON cannot carry it, so drop the frame.
            guard [origin.x, origin.y, extent.width, extent.height].allSatisfy(\.isFinite) else { return nil }
            return Frame(CGRect(origin: origin, size: extent))
        }
    }
}
