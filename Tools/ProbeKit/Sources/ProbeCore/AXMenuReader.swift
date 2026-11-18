import AppKit
import ApplicationServices

/// One menu or menu item as accessibility describes it.
public struct AXMenuNode: Codable, Sendable, Equatable {
    public var role: String
    public var title: String?
    public var enabled: Bool?
    /// Key equivalent such as `cmd+shift+C`; nil when the item has none.
    public var shortcut: String?
    /// Check mark or other state character.
    public var mark: String?
    /// True for an item without a title, which is how separators are exposed.
    public var separator: Bool
    public var frame: Frame?
    public var children: [AXMenuNode]
}

/// Reads the menu an app currently shows (context menu, pop-up or status-item menu) and the items
/// of its extras menu bar.
@MainActor
public enum AXMenuReader {
    /// The open menu: the one that holds the app's focused element, the one under `point`, or the
    /// first menu found among the app's direct children.
    public static func openMenu(app: TargetApp, at point: CGPoint?, maxDepth: Int = 6) throws -> AXMenuNode {
        try Permissions.requireAccessibility()
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 2)

        var candidates: [AXUIElement] = []
        if let point {
            var hit: AXUIElement?
            let systemWide = AXUIElementCreateSystemWide()
            if AXUIElementCopyElementAtPosition(systemWide, Float(point.x), Float(point.y), &hit) == .success, let hit {
                candidates.append(hit)
            }
        }
        candidates.append(contentsOf: elements(application, kAXFocusedUIElementAttribute))
        candidates.append(contentsOf: elements(application, kAXChildrenAttribute).filter { role($0) == kAXMenuRole })

        for candidate in candidates {
            if let menu = topMenu(from: candidate) { return node(menu, depth: 0, maxDepth: maxDepth) }
        }
        let chain = point.map { " [under the point: \(roleChain(at: $0).joined(separator: " < "))]" } ?? ""
        throw ProbeError.targetNotFound("\(app.name ?? "pid \(app.pid)") shows no menu (pass --at x,y inside it)\(chain)")
    }

    /// The app's status items (`AXExtrasMenuBar`), each with its frame and whatever menu it exposes.
    public static func extras(app: TargetApp, maxDepth: Int = 6) throws -> [AXMenuNode] {
        try Permissions.requireAccessibility()
        let application = AXUIElementCreateApplication(app.pid)
        AXUIElementSetMessagingTimeout(application, 2)
        guard let bar = elements(application, "AXExtrasMenuBar").first else {
            throw ProbeError.targetNotFound("\(app.name ?? "pid \(app.pid)") has no extras menu bar")
        }
        return elements(bar, kAXChildrenAttribute).map { node($0, depth: 0, maxDepth: maxDepth) }
    }

    /// Climbs from an element inside a menu (an item, a custom item view, or the menu itself) to
    /// the outermost menu that contains it; nil when no ancestor is a menu.
    private static func topMenu(from element: AXUIElement) -> AXUIElement? {
        var current = element
        var top: AXUIElement? = role(element) == kAXMenuRole ? element : nil
        for _ in 0..<32 {
            guard let parent = elements(current, kAXParentAttribute).first else { break }
            if role(parent) == kAXMenuRole { top = parent }
            current = parent
        }
        return top
    }

    /// Roles from the element under `point` up to its root, for diagnosing a failed lookup.
    public static func roleChain(at point: CGPoint) -> [String] {
        var hit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              var current = hit
        else { return [] }
        var chain = [role(current) ?? "?"]
        for _ in 0..<32 {
            guard let parent = elements(current, kAXParentAttribute).first else { break }
            chain.append(role(parent) ?? "?")
            current = parent
        }
        return chain
    }

    private static func node(_ element: AXUIElement, depth: Int, maxDepth: Int) -> AXMenuNode {
        let role = role(element) ?? "AXUnknown"
        let title = (copy(element, kAXTitleAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        let children = depth < maxDepth
            ? elements(element, kAXChildrenAttribute).map { node($0, depth: depth + 1, maxDepth: maxDepth) }
            : []
        return AXMenuNode(
            role: role,
            title: title,
            enabled: copy(element, kAXEnabledAttribute) as? Bool,
            shortcut: shortcut(element),
            mark: (copy(element, kAXMenuItemMarkCharAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 },
            separator: role == kAXMenuItemRole && title == nil && children.isEmpty,
            frame: frame(element),
            children: children
        )
    }

    /// `cmd+shift+C` from the item's command character, virtual key or glyph plus its modifier mask
    /// (bit 0 shift, bit 1 option, bit 2 control, bit 3 "no command").
    private static func shortcut(_ element: AXUIElement) -> String? {
        var key = (copy(element, kAXMenuItemCmdCharAttribute) as? String).flatMap { $0.isEmpty ? nil : $0 }
        if key == nil, let code = (copy(element, kAXMenuItemCmdVirtualKeyAttribute) as? NSNumber)?.intValue {
            key = "vk\(code)"
        }
        if key == nil, let glyph = (copy(element, kAXMenuItemCmdGlyphAttribute) as? NSNumber)?.intValue {
            key = "glyph\(glyph)"
        }
        guard let key else { return nil }
        let mask = (copy(element, kAXMenuItemCmdModifiersAttribute) as? NSNumber)?.intValue ?? 0
        var parts: [String] = []
        if mask & 4 != 0 { parts.append("ctrl") }
        if mask & 2 != 0 { parts.append("opt") }
        if mask & 1 != 0 { parts.append("shift") }
        if mask & 8 == 0 { parts.append("cmd") }
        let name = switch key {
        case "\u{8}", "\u{7F}": "delete"
        case "\r", "\n": "return"
        case "\u{3}": "enter"
        case "\u{1B}": "escape"
        case " ": "space"
        case "\t": "tab"
        default: key
        }
        parts.append(name)
        return parts.joined(separator: "+")
    }

    private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    private static func role(_ element: AXUIElement) -> String? {
        copy(element, kAXRoleAttribute) as? String
    }

    private static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        guard let value = copy(element, attribute) else { return [] }
        let candidates = (value as? [AnyObject]) ?? [value]
        return candidates.compactMap { candidate in
            CFGetTypeID(candidate) == AXUIElementGetTypeID() ? unsafeDowncast(candidate, to: AXUIElement.self) : nil
        }
    }

    private static func frame(_ element: AXUIElement) -> Frame? {
        var origin = CGPoint.zero
        var extent = CGSize.zero
        guard let position = copy(element, kAXPositionAttribute), let size = copy(element, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID(),
              AXValueGetValue(unsafeDowncast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeDowncast(size, to: AXValue.self), .cgSize, &extent)
        else { return nil }
        return Frame(CGRect(origin: origin, size: extent))
    }
}
