import Foundation
import PastoCore
@testable import PastoOnboarding
import Testing

/// Pasto's welcome content in each language the module ships.
struct WelcomeContentCatalogTests {
    private let english = WelcomeContentStrings(languageCode: "en")!
    private let spanish = WelcomeContentStrings(languageCode: "es")!

    private func content(_ strings: WelcomeContentStrings, shortcut: String? = "⇧⌘V") -> WelcomeContent {
        WelcomeContentCatalog.content(strings: strings, activationShortcut: shortcut, application: nil)
    }

    private func titles(_ entries: [WelcomeContent.Entry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .note(let title, _), .link(let title, _, _): title
            }
        }
    }

    private func texts(_ entries: [WelcomeContent.Entry]) -> [String] {
        entries.map { entry in
            switch entry {
            case .note(_, let text): text
            case .link(_, _, let pageTitle): pageTitle
            }
        }
    }

    @Test func threeHistoryNotesAndARedPinboardWithANoteThenThreeLinks() {
        let content = content(english)

        #expect(content.historyEntries.count == 3)
        #expect(content.historyEntries.allSatisfy { if case .note = $0 { true } else { false } })
        #expect(content.pinboardColor == .red)
        #expect(content.pinboardEntries.count == 4)
        if case .note = content.pinboardEntries[0] {} else { Issue.record("The pinboard does not open with a note") }
        #expect(content.pinboardEntries.dropFirst().allSatisfy { if case .link = $0 { true } else { false } })
    }

    @Test func theLinksArePastosOwn() {
        let urls = content(english).pinboardEntries.compactMap { entry -> String? in
            if case .link(_, let url, _) = entry { url.absoluteString } else { nil }
        }

        #expect(urls == [
            "https://pasto.jnjambrino.com",
            "https://pasto.jnjambrino.com/contact",
            "https://pasto.jnjambrino.com/releases",
        ])
    }

    @Test func inEnglish() {
        let content = content(english)

        #expect(content.pinboardName == "Pasto Links")
        #expect(titles(content.historyEntries) == ["Paste Again", "Find It Fast", "Keep What Matters"])
        #expect(titles(content.pinboardEntries) == ["Welcome to Pasto", "Get to Know Pasto", "Need a Hand?", "What’s New"])
        #expect(texts(content.historyEntries)[0].contains("Press ⇧⌘V in any app to open Pasto"))
        #expect(texts(content.historyEntries)[0].contains("press Return to paste it"))
        #expect(texts(content.historyEntries)[0].contains("Press Space"))
        #expect(texts(content.historyEntries)[1].contains("start typing to search"))
        #expect(texts(content.historyEntries)[2].contains("Right-click an item and choose Pin"))
        #expect(texts(content.pinboardEntries)[0].contains("⌘O"))
    }

    @Test func inSpanish() {
        let content = content(spanish)

        #expect(content.pinboardName == "Enlaces de Pasto")
        #expect(titles(content.historyEntries) == ["Pega de nuevo", "Encuéntralo rápido", "Guarda lo importante"])
        #expect(titles(content.pinboardEntries) == ["Te damos la bienvenida", "Conoce Pasto", "¿Necesitas ayuda?", "Novedades"])
        #expect(texts(content.historyEntries)[0].contains("Pulsa ⇧⌘V en cualquier app para abrir Pasto"))
        #expect(texts(content.historyEntries)[0].contains("pulsa Retorno para pegarlo"))
        #expect(texts(content.historyEntries)[2].contains("elige Fijar"))
        #expect(texts(content.pinboardEntries)[0].contains("⌘O"))
    }

    @Test func withoutAShortcutTheFirstNotePointsToTheMenuBar() {
        #expect(texts(content(english, shortcut: nil).historyEntries)[0].contains("from its icon in the menu bar"))
        #expect(texts(content(spanish, shortcut: nil).historyEntries)[0].contains("desde su icono en la barra de menús"))
    }

    @Test func everyTextIsTranslatedAndNoneIsAKey() {
        let englishTexts = titles(content(english).historyEntries + content(english).pinboardEntries)
            + texts(content(english).historyEntries + content(english).pinboardEntries)
            + [english.pinboardName, english.pasteText(shortcut: nil)]
        let spanishTexts = titles(content(spanish).historyEntries + content(spanish).pinboardEntries)
            + texts(content(spanish).historyEntries + content(spanish).pinboardEntries)
            + [spanish.pinboardName, spanish.pasteText(shortcut: nil)]

        for (englishText, spanishText) in zip(englishTexts, spanishTexts) {
            #expect(!englishText.isEmpty)
            #expect(!englishText.hasPrefix("welcome."))
            #expect(!spanishText.hasPrefix("welcome."))
            #expect(englishText != spanishText)
        }
    }
}
