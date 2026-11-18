@testable import PastoCore
import Testing

struct HTMLCharacterReferencesTests {
    private func text(_ string: String) -> String {
        HTMLCharacterReferences.decode(string, inAttribute: false)
    }

    @Test func namedAndNumericReferencesAreDecoded() {
        #expect(text("&lt;b&gt; &amp; &quot;x&quot; &apos;y&apos;") == "<b> & \"x\" 'y'")
        #expect(text("Caf&eacute; &mdash; &hellip;&rsquo;&laquo;&raquo;&nbsp;") == "Café — …’«»\u{A0}")
        #expect(text("&#233;&#xE9;&#XE9;&#x1F600;&#39;") == "ééé😀'")
    }

    @Test func numbersHTMLDoesNotAllowBecomeTheReplacementCharacter() {
        #expect(text("&#0;&#xD800;&#x110000;&#99999999999;") == "\u{FFFD}\u{FFFD}\u{FFFD}\u{FFFD}")
        // C1 controls are read as windows-1252.
        #expect(text("&#150;&#128;&#x93;&#x94;") == "–€“”")
    }

    @Test func unknownNamesAndLoneAmpersandsStay() {
        #expect(text("&unknown; & &; &#; &#x; AT&T") == "&unknown; & &; &#; &#x; AT&T")
    }

    @Test func oldNamesWorkWithoutASemicolonExceptInsideAValueThatContinues() {
        #expect(text("&amp &copy 2024 &notit;") == "& © 2024 ¬it;")
        #expect(HTMLCharacterReferences.decode("/a?b=1&copy=2&amp;c&lt", inAttribute: true) == "/a?b=1&copy=2&c<")
        #expect(HTMLCharacterReferences.decode("&copyright", inAttribute: true) == "&copyright")
        #expect(text("&copyright") == "©right")
    }
}
