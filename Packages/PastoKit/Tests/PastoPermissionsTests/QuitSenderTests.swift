import Foundation
@testable import PastoPermissions
import Testing

/// Who asked Pasto to quit. The Privacy & Security pane's "Quit & Reopen" comes from
/// `com.apple.settings.PrivacySecurity.extension`, logged as "Privacy & Security (System
/// Settings)" on macOS 27.2.
struct QuitSenderTests {
    @Test(arguments: [
        "com.apple.systempreferences",
        "com.apple.settings.PrivacySecurity.extension",
        "com.apple.preference.security",
    ])
    func systemSettingsAndItsPanesAreSystemSettings(_ bundleIdentifier: String) {
        #expect(QuitSender(bundleIdentifier: bundleIdentifier, executablePath: nil) == .systemSettings)
    }

    @Test func theSettingsExtensionIsKnownByItsPathAlone() {
        let path = "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/MacOS/SecurityPrivacyExtension"
        #expect(QuitSender(bundleIdentifier: nil, executablePath: path) == .systemSettings)
        #expect(QuitSender(bundleIdentifier: nil, executablePath: "/System/Applications/System Settings.app/Contents/MacOS/System Settings") == .systemSettings)
    }

    @Test func otherProcessesAreNamed() {
        #expect(QuitSender(bundleIdentifier: "com.apple.dock", executablePath: "/System/Library/CoreServices/Dock.app/Contents/MacOS/Dock") == .other("com.apple.dock"))
        #expect(QuitSender(bundleIdentifier: nil, executablePath: "/usr/bin/osascript") == .other("/usr/bin/osascript"))
        // A look-alike identifier is not System Settings.
        #expect(QuitSender(bundleIdentifier: "com.apple.settingsfake", executablePath: nil) == .other("com.apple.settingsfake"))
    }

    @Test func nothingToGoOnIsUnknown() {
        #expect(QuitSender(bundleIdentifier: nil, executablePath: nil) == .unknown)
        #expect(QuitSender(processIdentifier: 0) == .unknown)
    }

    @Test func anExtensionIsNamedByTheBundleAroundItsExecutable() {
        let path = "/System/Library/ExtensionKit/Extensions/SecurityPrivacyExtension.appex/Contents/MacOS/SecurityPrivacyExtension"
        #expect(QuitSender.bundleIdentifier(ofExecutableAt: path) == "com.apple.settings.PrivacySecurity.extension")
    }
}
