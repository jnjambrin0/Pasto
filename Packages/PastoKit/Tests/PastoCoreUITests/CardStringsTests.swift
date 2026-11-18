import PastoCore
import Testing
@testable import PastoCoreUI

/// The strings of Resources/Localizable.xcstrings, in each language the module ships.
@Suite struct CardStringsTests {
    let english = CardStrings(languageCode: "en")!
    let spanish = CardStrings(languageCode: "es")!

    @Test func characterCountInEnglish() {
        #expect(english.characterCount(0) == "0 characters")
        #expect(english.characterCount(1) == "1 character")
        #expect(english.characterCount(31) == "31 characters")
        #expect(english.characterCount(3000) == "3,000 characters")
    }

    @Test func characterCountInSpanish() {
        #expect(spanish.characterCount(1) == "1 carácter")
        #expect(spanish.characterCount(31) == "31 caracteres")
        #expect(spanish.characterCount(12345) == "12.345 caracteres")
    }

    @Test func typeNamesInEnglish() {
        #expect(english.typeName(for: .text) == "Text")
        #expect(english.typeName(for: .link) == "Link")
        #expect(english.typeName(for: .image) == "Image")
        #expect(english.typeName(for: .color) == "Color")
        #expect(english.typeName(for: .unknown) == "Unknown")
        #expect(english.typeName(for: .files) == "File")
        #expect(english.typeName(for: .files, fileCount: 1) == "File")
        #expect(english.typeName(for: .files, fileCount: 3) == "3 files")
        // A file item always holds at least one file.
        #expect(english.typeName(for: .files, fileCount: 0) == "File")
    }

    @Test func typeNamesInSpanish() {
        #expect(spanish.typeName(for: .text) == "Texto")
        #expect(spanish.typeName(for: .link) == "Enlace")
        #expect(spanish.typeName(for: .image) == "Imagen")
        #expect(spanish.typeName(for: .color) == "Color")
        #expect(spanish.typeName(for: .unknown) == "Desconocido")
        #expect(spanish.typeName(for: .files) == "Archivo")
        #expect(spanish.typeName(for: .files, fileCount: 3) == "3 archivos")
    }

    @Test func captions() {
        #expect(english.multipleFiles == "Multiple files")
        #expect(spanish.multipleFiles == "Varios archivos")
        #expect(english.justNow == "just now")
        #expect(spanish.justNow == "ahora mismo")
        #expect(english.previewUnavailable == "No preview available")
        #expect(spanish.previewUnavailable == "Vista previa no disponible")
    }

    @Test func everyTypeHasAName() {
        for type in ItemType.allCases {
            #expect(!english.typeName(for: type).isEmpty)
            #expect(!english.typeName(for: type).hasPrefix("card."))
            #expect(!spanish.typeName(for: type).hasPrefix("card."))
        }
    }

    @Test func unknownLanguagesHaveNoStrings() {
        #expect(CardStrings(languageCode: "xx") == nil)
    }
}
