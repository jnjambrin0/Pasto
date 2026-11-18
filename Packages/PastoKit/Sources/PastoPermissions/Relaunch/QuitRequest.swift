import AppKit

/// What made Pasto quit, as far as the termination can tell.
///
/// When System Settings quits an app after a privacy grant ("Quit & Reopen"), the app receives
/// the standard quit Apple Event from the Privacy & Security settings extension
/// (`com.apple.settings.PrivacySecurity.extension`, "Privacy & Security (System Settings)" in the
/// log). Quitting from Pasto's own menu sends no event.
public enum QuitRequest: Equatable, Sendable {
    /// Pasto quit itself: its menu, ⌘Q, or code calling `terminate`.
    case direct
    /// Another process sent the quit Apple Event. `hasReason` when it says why — logging out,
    /// restarting or shutting down.
    case appleEvent(sender: QuitSender, hasReason: Bool)

    /// The request `event` carries: `direct` unless it is the quit Apple Event.
    @MainActor
    init(event: NSAppleEventDescriptor?) {
        guard let event, event.eventClass == AEEventClass(kCoreEventClass), event.eventID == AEEventID(kAEQuitApplication) else {
            self = .direct
            return
        }
        let reasonKeyword = AEKeyword(kAEQuitReason)
        let hasReason = event.paramDescriptor(forKeyword: reasonKeyword) != nil
            || event.attributeDescriptor(forKeyword: reasonKeyword) != nil
        let senderPID = event.attributeDescriptor(forKeyword: AEKeyword(keySenderPIDAttr))?.int32Value ?? 0
        self = .appleEvent(sender: QuitSender(processIdentifier: senderPID), hasReason: hasReason)
    }
}
