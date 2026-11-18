import Foundation
import Testing
@testable import PastoCoreUI

/// The short form of a URL that a link card shows.
@Suite struct ShortURLTests {
    func short(_ string: String) -> String {
        ShortURL.string(for: URL(string: string)!)
    }

    @Test func dropsSchemeWwwAndTrailingSlash() {
        #expect(short("https://www.apple.com/macos/") == "apple.com/macos")
        #expect(short("http://example.com") == "example.com")
        #expect(short("https://example.com/") == "example.com")
    }

    @Test func keepsTheQuery() {
        #expect(short("https://developer.apple.com/documentation/appkit/nspasteboard?language=swift&probe=seed")
            == "developer.apple.com/documentation/appkit/nspasteboard?language=swift&probe=seed")
    }

    @Test func keepsSchemesThatDoNotStartWithLowercaseHTTP() {
        #expect(short("ftp://files.example.com/pub/") == "ftp://files.example.com/pub")
        #expect(short("HTTPS://Example.com/a") == "HTTPS://Example.com/a")
    }

    @Test func everyWwwOfTheHostIsDropped() {
        #expect(short("https://docs.www.example.com/a") == "docs.example.com/a")
        #expect(short("https://wwwexample.com") == "wwwexample.com")
    }

    @Test func thePathIsShownDecoded() {
        #expect(short("https://example.com/a%20b") == "example.com/a b")
    }

    @Test func urlsWithoutAHostAreShownFromTheirPath() {
        #expect(short("mailto:someone@example.com") == "mailto://someone@example.com")
        #expect(short("file:///tmp/a.txt") == "file:///tmp/a.txt")
    }
}
