import AppKit
import PastoInput
import Testing

/// A damaged shortcut never takes the app down.
struct HotKeyCenterTests {
    @Test func aKeyCodeNoKeyHasIsRefusedWithoutStoppingTheApp() {
        let center = HotKeyCenter()

        center.register(Shortcut(keyCode: Int(UInt32.max) + 1, modifiers: .command), caller: "test") {}
        center.register(Shortcut(keyCode: -1, modifiers: .command), caller: "test") {}
        center.unregister(caller: "test")
    }
}
