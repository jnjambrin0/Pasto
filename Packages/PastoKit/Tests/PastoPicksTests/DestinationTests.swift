import CoreGraphics
@testable import PastoPicks
import Testing

/// What decides the destination field: the table of applications, the screenshot's size, the
/// window chosen and the late reranking.
struct DestinationTests {
    @Test func applicationsAreMatchedByPrefix() {
        #expect(ApplicationFieldKinds.fieldKind(ofApplication: "com.jetbrains.intellij") == .code)
        #expect(ApplicationFieldKinds.fieldKind(ofApplication: "com.apple.Terminal") == .terminal)
        #expect(ApplicationFieldKinds.fieldKind(ofApplication: "com.apple.MobileSMS") == .chat)
        #expect(ApplicationFieldKinds.fieldKind(ofApplication: "com.apple.TextEdit") == nil)
    }

    @Test func prefixesMatchTheRealIdentifiersCaseSensitively() {
        #expect(ApplicationFieldKinds.fieldKind(ofApplication: "com.apple.freeform") == .canvas)
        #expect(ApplicationFieldKinds.fieldKind(ofApplication: "com.apple.Freeform") == nil)
    }

    @Test func theScreenshotIsTakenAtTheWindowsResolution() {
        let size = ScreenContextReader.pixelSize(of: CGRect(x: 10, y: 20, width: 800.6, height: 600), scale: 2)
        #expect(size?.width == 1601)
        #expect(size?.height == 1200)
    }

    @Test func aHugeWindowIsScaledDownToTheLimit() {
        let size = ScreenContextReader.pixelSize(of: CGRect(x: 0, y: 0, width: 20000, height: 5000), scale: 2)
        #expect(size?.width == 16384)
        #expect(size?.height == 4096)
    }

    @Test func aWindowLessThanAPixelIsNotCaptured() {
        #expect(ScreenContextReader.pixelSize(of: CGRect(x: 0, y: 0, width: 100, height: 0.4), scale: 1) == nil)
    }

    @Test func theWindowMustBeTheApplicationsOnScreenAndTitled() {
        #expect(ScreenContextReader.isCandidate(processID: 42, isOnScreen: true, title: "Notes", of: 42))
        #expect(!ScreenContextReader.isCandidate(processID: 7, isOnScreen: true, title: "Notes", of: 42))
        #expect(!ScreenContextReader.isCandidate(processID: 42, isOnScreen: false, title: "Notes", of: 42))
        #expect(!ScreenContextReader.isCandidate(processID: 42, isOnScreen: true, title: "", of: 42))
        #expect(!ScreenContextReader.isCandidate(processID: 42, isOnScreen: true, title: nil, of: 42))
        #expect(!ScreenContextReader.isCandidate(processID: nil, isOnScreen: true, title: "Notes", of: 42))
    }

    // MARK: - Late reranking

    private let ranked = DestinationContext(appBundleIdentifier: "com.example.editor", fieldKind: .text, isSecureInput: false)

    @Test func aDifferentFieldSeenLateRanksAgain() {
        let fieldKind = PicksProvider.lateFieldKind(rankedContext: ranked, hasEntry: true, isStripTouched: false, screenFieldKind: .code)
        #expect(fieldKind == .code)
    }

    @Test func noReranking() {
        var secure = ranked
        secure.isSecureInput = true
        let cases: [(DestinationContext?, Bool, Bool, FieldKind?)] = [
            // Nothing ranked yet.
            (nil, true, false, .code),
            // Secure input.
            (secure, true, false, .code),
            // The suggestions' entry was already closed.
            (ranked, false, false, .code),
            // The user is using them.
            (ranked, true, true, .code),
            // The window told nothing.
            (ranked, true, false, nil),
            // The same field.
            (ranked, true, false, .text),
        ]
        for (context, hasEntry, isTouched, screen) in cases {
            #expect(PicksProvider.lateFieldKind(rankedContext: context, hasEntry: hasEntry, isStripTouched: isTouched, screenFieldKind: screen) == nil)
        }
    }

    @Test func fieldsAndTheClassesThatSuitThem() {
        #expect(FieldKind.password.suitedClasses.isEmpty)
        #expect(FieldKind.text.suitedClasses.isEmpty)
        #expect(FieldKind.url.suitedClasses == [.link])
        #expect(FieldKind.cell.suitedClasses.contains(.money))
        #expect(!FieldKind.chat.suitedClasses.contains(.secret))
    }
}
