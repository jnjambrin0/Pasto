import AppKit
import PastoCore
import Testing
@testable import PastoCoreUI

/// What VoiceOver reads for a card.
@Suite struct CardAccessibilityLabelTests {
    static let english = CardAccessibilityLabel(languageCode: "en")!
    static let spanish = CardAccessibilityLabel(languageCode: "es")!

    func model(
        typeName: String = "Text",
        customTitle: String? = nil,
        application: String? = "Safari",
        content: ItemCellModel.Content = .text(.init(attributedText: NSAttributedString(string: "Dear Ana,\n\nsee you   soon"), characterCount: 25))
    ) -> ItemCellModel {
        ItemCellModel(
            id: ItemID(rawValue: "item"), type: .text, customTitle: customTitle, typeName: typeName,
            date: .now, sourceApplication: application.map { .init(name: $0) }, content: content
        )
    }

    @Test func titleDateApplicationAndContent() {
        #expect(Self.english.label(for: model(), relativeDate: "5 minutes ago")
            == "Text, copied 5 minutes ago from Safari: Dear Ana, see you soon")
        #expect(Self.spanish.label(for: model(typeName: "Texto"), relativeDate: "hace 5 minutos")
            == "Texto, de Safari, hace 5 minutos: Dear Ana, see you soon")
    }

    @Test func withoutDateOrApplication() {
        #expect(Self.english.label(for: model(), relativeDate: nil) == "Text, from Safari: Dear Ana, see you soon")
        #expect(Self.english.label(for: model(application: nil), relativeDate: "just now")
            == "Text, copied just now: Dear Ana, see you soon")
        #expect(Self.english.label(for: model(customTitle: "Letter", application: nil), relativeDate: nil)
            == "Letter: Dear Ana, see you soon")
    }

    @Test func summaries() {
        let link = ItemCellModel.Content.link(.init(url: URL(string: "https://example.com/a")!))
        #expect(CardAccessibilityLabel.summary(of: link) == "https://example.com/a")
        let titled = ItemCellModel.Content.link(.init(url: URL(string: "https://example.com/a")!, title: "Example"))
        #expect(CardAccessibilityLabel.summary(of: titled) == "Example")
        #expect(CardAccessibilityLabel.summary(of: .image(.init(width: 640, height: 400))) == "640 × 400")
        #expect(CardAccessibilityLabel.summary(of: .files(.init(paths: ["/tmp/a.txt", "/Users/b/c.pdf"]))) == "a.txt, c.pdf")
        #expect(CardAccessibilityLabel.summary(of: .unknown) == nil)
        #expect(CardAccessibilityLabel.summary(of: .text(.init(attributedText: NSAttributedString(string: " \n"), characterCount: 2))) == nil)
    }

    @Test func excerptStopsAtAWord() {
        let words = Array(repeating: "word", count: 40).joined(separator: " ")
        let excerpt = CardAccessibilityLabel.excerpt(words)
        #expect(excerpt.hasSuffix("word…"))
        #expect(excerpt.count <= CardAccessibilityLabel.excerptLength + 1)
        let long = String(repeating: "x", count: 200)
        #expect(CardAccessibilityLabel.excerpt(long) == String(repeating: "x", count: CardAccessibilityLabel.excerptLength) + "…")
    }
}
