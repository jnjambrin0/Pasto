import Carbon.HIToolbox

/// Virtual key codes of the keys Pasto's views handle directly. These are layout-independent.
public nonisolated enum KeyCode {
    public static let returnKey = UInt16(kVK_Return)
    public static let enter = UInt16(kVK_ANSI_KeypadEnter)
    public static let tab = UInt16(kVK_Tab)
    public static let space = UInt16(kVK_Space)
    public static let delete = UInt16(kVK_Delete)
    public static let forwardDelete = UInt16(kVK_ForwardDelete)
    public static let escape = UInt16(kVK_Escape)
    public static let home = UInt16(kVK_Home)
    public static let end = UInt16(kVK_End)
    public static let pageUp = UInt16(kVK_PageUp)
    public static let pageDown = UInt16(kVK_PageDown)
    public static let leftArrow = UInt16(kVK_LeftArrow)
    public static let rightArrow = UInt16(kVK_RightArrow)
    public static let downArrow = UInt16(kVK_DownArrow)
    public static let upArrow = UInt16(kVK_UpArrow)
}
