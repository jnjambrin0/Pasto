import AppKit
@testable import PastoPermissions
import Testing

/// Where a permission window sits: over every application, except System Settings and the
/// system's own prompts while the user deals with them.
struct PermissionWindowLevelTests {
    @Test(arguments: [true, false])
    func theWindowStepsDownWhileSystemSettingsIsInFront(includesAccessibilityPrompts: Bool) {
        let level = PermissionWindowLevel.level(
            frontmostBundleIdentifier: "com.apple.systempreferences",
            includesAccessibilityPrompts: includesAccessibilityPrompts
        )

        #expect(level == .normal)
    }

    @Test func forAccessibilityItAlsoStepsDownForTheSystemsPrompt() {
        let prompt = "com.apple.accessibility.universalAccessAuthWarn"

        #expect(PermissionWindowLevel.level(frontmostBundleIdentifier: prompt, includesAccessibilityPrompts: true) == .normal)
        #expect(PermissionWindowLevel.level(frontmostBundleIdentifier: prompt, includesAccessibilityPrompts: false) == .modalPanel)
    }

    @Test func systemSettingsIsMatchedWholeNotByItsBeginning() {
        let level = PermissionWindowLevel.level(
            frontmostBundleIdentifier: "com.apple.systempreferences.extension",
            includesAccessibilityPrompts: false
        )

        #expect(level == .modalPanel)
    }

    @Test(arguments: ["com.apple.Safari", "jnjambrino.Pasto", nil] as [String?])
    func theWindowFloatsOverEveryOtherApplication(bundleIdentifier: String?) {
        let level = PermissionWindowLevel.level(frontmostBundleIdentifier: bundleIdentifier, includesAccessibilityPrompts: true)

        #expect(level == .modalPanel)
    }
}
