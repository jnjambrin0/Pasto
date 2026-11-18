import Foundation

/// What a window that comes and goes — the main panel — tells the views in it that pause while it
/// is out of sight, such as the dates of the cards (`DateLabel`).
public enum WindowVisibility {
    /// Posted with the window as object right before it is ordered in, before anything in it is
    /// drawn: the moment to bring what is shown up to date. The occlusion notification only
    /// arrives once the window is already on screen.
    public static let willShowNotification = Notification.Name("jnjambrino.Pasto.windowWillShow")
}
