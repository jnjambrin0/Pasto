import CoreGraphics
import Foundation

/// One window as the window server describes it. Bounds are screen points with a top-left origin.
public struct WindowInfo: Codable, Sendable, Equatable {
    public let id: UInt32
    public let pid: Int32
    public let owner: String?
    public let layer: Int
    public let bounds: Frame
    public let alpha: Double
    public let isOnscreen: Bool
    public let name: String?
    /// `none`, `readOnly` or `readWrite`: whether other processes may capture the window.
    public let sharingState: String

    init?(dictionary: [String: Any]) {
        guard let id = dictionary[kCGWindowNumber as String] as? NSNumber,
              let pid = dictionary[kCGWindowOwnerPID as String] as? NSNumber,
              let boundsDictionary = dictionary[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: boundsDictionary)
        else { return nil }
        self.id = id.uint32Value
        self.pid = pid.int32Value
        self.owner = dictionary[kCGWindowOwnerName as String] as? String
        self.layer = (dictionary[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0
        self.bounds = Frame(bounds)
        self.alpha = (dictionary[kCGWindowAlpha as String] as? NSNumber)?.doubleValue ?? 1
        self.isOnscreen = (dictionary[kCGWindowIsOnscreen as String] as? NSNumber)?.boolValue ?? false
        self.name = dictionary[kCGWindowName as String] as? String
        self.sharingState = switch (dictionary[kCGWindowSharingState as String] as? NSNumber)?.intValue {
        case 0: "none"
        case 1: "readOnly"
        case 2: "readWrite"
        default: "unknown"
        }
    }
}

public enum WindowList {
    /// Every window known to the window server, on screen or not, sorted by layer then id.
    public static func all() -> [WindowInfo] {
        describe(CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID))
            .sorted { ($0.layer, $0.id) < ($1.layer, $1.id) }
    }

    public static func windows(ofPID pid: Int32) -> [WindowInfo] {
        all().filter { $0.pid == pid }
    }

    /// Current state of a single window, on screen or not; nil once it no longer exists.
    ///
    /// `CGWindowListCopyWindowInfo(.optionIncludingWindow, id)` would be the obvious call, but it
    /// returns nothing for a window that is ordered out, which is exactly the state a hidden panel
    /// is in before its show animation.
    public static func window(id: UInt32) -> WindowInfo? {
        // The array carries the raw window id in place of an object, hence the nil callbacks.
        var rawID = UnsafeRawPointer(bitPattern: UInt(id))
        guard let ids = CFArrayCreate(kCFAllocatorDefault, &rawID, 1, nil) else { return nil }
        return describe(CGWindowListCreateDescriptionFromArray(ids)).first
    }

    /// The app's window with the largest area; ties go to the on-screen one, then the lowest id.
    public static func largest(of app: TargetApp) throws -> WindowInfo {
        let ranked = windows(ofPID: app.pid).sorted { a, b in
            if a.bounds.area != b.bounds.area { return a.bounds.area > b.bounds.area }
            if a.isOnscreen != b.isOnscreen { return a.isOnscreen }
            return a.id < b.id
        }
        guard let largest = ranked.first else {
            throw ProbeError.targetNotFound("\(app.name ?? "pid \(app.pid)") has no windows")
        }
        return largest
    }

    private static func describe(_ list: CFArray?) -> [WindowInfo] {
        let dictionaries = list as? [[String: Any]] ?? []
        return dictionaries.compactMap(WindowInfo.init(dictionary:))
    }
}
