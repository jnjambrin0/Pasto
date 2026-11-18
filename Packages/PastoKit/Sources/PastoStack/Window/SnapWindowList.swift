import AppKit
import CoreGraphics

/// Reads the windows on screen from the window server, for the guides of a drag. Frames, layers
/// and opacity need no permission.
enum SnapWindowList {
    /// Front to back. Entries that lack any of the values are left out.
    static func onScreen() -> [SnapWindow] {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let entries = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]],
              let mainScreenMaxY = NSScreen.screens.first?.frame.maxY
        else { return [] }

        return entries.compactMap { entry in
            guard let boundsValue = entry[kCGWindowBounds as String] as? NSDictionary,
                  let bounds = CGRect(dictionaryRepresentation: boundsValue),
                  let layer = entry[kCGWindowLayer as String] as? Int,
                  let alpha = entry[kCGWindowAlpha as String] as? Double,
                  let number = entry[kCGWindowNumber as String] as? Int
            else { return nil }
            return SnapWindow(
                frame: StackWindowLayout.screenRect(fromWindowServer: bounds, mainScreenMaxY: mainScreenMaxY),
                layer: layer,
                alpha: alpha,
                number: number
            )
        }
    }
}
