import Foundation
@testable import PastoCore
import Testing

struct ItemTypeDetectorTests {
    private func type(_ representations: KeyValuePairs<String, String>) -> ItemType {
        ItemTypeDetector.type(of: [PasteboardItemSnapshot(strings: representations)])
    }

    private func type(ofText text: String) -> ItemType {
        ItemTypeDetector.type(of: [.text(text)])
    }

    // MARK: - Base type by priority

    @Test func nothingKnownIsUnknown() {
        #expect(ItemTypeDetector.type(of: []) == .unknown)
        #expect(type(["com.example.private": "x", "public.html": "<p>x</p>"]) == .unknown)
    }

    @Test func aFileURLMakesItFilesWhateverElseThereIs() {
        #expect(type(["public.file-url": "file:///tmp/a.txt"]) == .files)
        #expect(type(["public.tiff": "tiff", "public.file-url": "file:///tmp/a.tiff", "public.utf8-plain-text": "a.tiff"]) == .files)
    }

    @Test func formattedTextIsTextEvenWithAnImage() {
        #expect(type(["public.png": "png", "public.rtf": "{\\rtf1 hello}", "public.utf8-plain-text": "hello"]) == .text)
    }

    @Test(arguments: ["public.png", "public.jpeg", "public.heic", "public.tiff", "com.apple.icns"])
    func imageTypesMakeAnImage(imageType: String) {
        #expect(type([imageType: "image", "public.utf8-plain-text": "caption"]) == .image)
    }

    @Test(arguments: ["public.utf8-plain-text", "public.plain-text", "public.text"])
    func plainTextTypesMakeText(textType: String) {
        #expect(type([textType: "hello"]) == .text)
    }

    @Test func theTypesOfAllItemsCount() {
        let items: [PasteboardItemSnapshot] = [.text("caption"), PasteboardItemSnapshot(strings: ["public.png": "png"])]

        #expect(ItemTypeDetector.type(of: items) == .image)
    }

    // MARK: - Colours

    @Test(arguments: [
        ("#1A2B3C", ItemType.color),
        ("#123456", .color),
        ("1A2B3C", .color),
        ("abcdef", .color),
        ("#abcdef", .color),
        ("123456", .text),
        ("#FFF", .text),
        ("#1A2B3C80", .text),
        ("#1A2B3G", .text),
        (" #1A2B3C", .text),
        ("#1A2B3C ", .text),
        ("#1A2B3C\n", .text),
        ("color: #1A2B3C", .text),
        ("rgb(26, 43, 60)", .text),
    ])
    func sixHexadecimalDigitsAreAColour(string: String, expected: ItemType) {
        #expect(type(ofText: string) == expected)
    }

    @Test func aColourIsReadFromTheFirstItemOnly() {
        #expect(ItemTypeDetector.type(of: [.text("hello"), .text("#1A2B3C")]) == .text)
        #expect(ItemTypeDetector.type(of: [.text("#1A2B3C"), .text("hello")]) == .color)
    }

    // MARK: - Links

    @Test(arguments: [
        ("https://ejemplo.com", ItemType.link),
        ("https://ejemplo.com/a/b?c=d#e", .link),
        ("https://ejemplo.com\n", .link),
        ("mira https://ejemplo.com", .text),
        ("https://ejemplo.com y más", .text),
        ("https://ejemplo.com https://otro.com", .text),
        ("ejemplo.com", .text),
        ("mailto:alguien@ejemplo.com", .text),
        ("hola", .text),
        ("", .text),
    ])
    func textIsALinkOnlyIfItIsOneAndNothingElse(string: String, expected: ItemType) {
        #expect(type(ofText: string) == expected)
    }

    @Test func anItemOfferedAsAURLIsALinkUnlessItsStringSaysOtherwise() {
        #expect(type(["public.url": "https://ejemplo.com", "public.utf8-plain-text": "https://ejemplo.com"]) == .link)
        // No link in the string to contradict the type.
        #expect(type(["public.url": "https://ejemplo.com", "public.utf8-plain-text": "Ejemplo"]) == .link)
        #expect(type(["public.url": "https://ejemplo.com"]) == .link)
        // The string is more than a link.
        #expect(type(["public.url": "https://ejemplo.com", "public.utf8-plain-text": "mira https://ejemplo.com"]) == .text)
    }

    @Test func anyAddressWithASchemeAndAHostIsACandidate() {
        #expect(PasteboardItemSnapshot.text("ftp://servidor/x").url != nil)
        #expect(PasteboardItemSnapshot.text("miapp://host").url != nil)
        #expect(PasteboardItemSnapshot.text("miapp:host").url == nil)
        #expect(PasteboardItemSnapshot.text("/tmp/fichero").url == nil)
    }
}

struct LinkNormalizerTests {
    @Test(arguments: [
        ("https://ejemplo.com", "https://ejemplo.com/"),
        ("https://ejemplo.com/", "https://ejemplo.com/"),
        ("https://ejemplo.com?q=1#f", "https://ejemplo.com/?q=1#f"),
        ("https://ejemplo.com#f", "https://ejemplo.com/#f"),
        ("https://ejemplo.com/a/", "https://ejemplo.com/a"),
        ("https://ejemplo.com/a", "https://ejemplo.com/a"),
        ("https://ejemplo.com/a/?q=1/#f/", "https://ejemplo.com/a?q=1/#f/"),
        ("HTTPS://Ejemplo.com/A/", "HTTPS://Ejemplo.com/A"),
        ("ftp://ejemplo.com", "ftp://ejemplo.com"),
        ("mailto:alguien@ejemplo.com", "mailto:alguien@ejemplo.com"),
        ("no es una dirección", "no es una dirección"),
    ])
    func onlyTheEndOfAWebAddressPathChanges(string: String, expected: String) {
        #expect(LinkNormalizer.normalized(string) == expected)
    }
}
