import Foundation
@testable import PastoCore
import Testing

/// Reading a page's head as a browser's parser would, on the kind of markup pages really have.
struct HTMLHeadTests {
    private func head(_ html: String, charset: String? = nil) -> HTMLHead {
        HTMLHead(parsing: Data(html.utf8), charset: charset)
    }

    @Test func metaAndLinkTagsAreReadWithTheirAttributesDecoded() {
        let head = head("""
        <!DOCTYPE html><html lang="es"><HEAD>
        <META PROPERTY="OG:Title" CONTENT="Caf&eacute; &amp; t&#233; &#x1F600;">
        <meta name=twitter:image content=/img/a.png>
        <meta itemprop="image" content='/b.png' >
        <link rel="Shortcut Icon" href="/favicon.ico?v=1&amp;x=2">
        <link rel="apple-touch-icon" sizes="180x180" type="image/png" href="/touch.png"/>
        <base href="/sub/"><base href="/other/">
        </head><body></body></html>
        """)

        #expect(head.metas == [
            HTMLHead.Meta(property: "og:title", content: "Café & té 😀"),
            HTMLHead.Meta(name: "twitter:image", content: "/img/a.png"),
            HTMLHead.Meta(itemprop: "image", content: "/b.png"),
        ])
        #expect(head.links == [
            HTMLHead.Link(rel: "shortcut icon", href: "/favicon.ico?v=1&x=2"),
            HTMLHead.Link(rel: "apple-touch-icon", href: "/touch.png", sizes: "180x180", type: "image/png"),
        ])
        #expect(head.baseHref == "/sub/")
    }

    @Test func theTitleIsTheFirstOneAndItsTextIsTakenAsWritten() {
        #expect(head("<title>\n  Uno &amp; <b>dos</b>  </title><title>Tres</title>").title == "\n  Uno & <b>dos</b>  ")
        #expect(head("<head><title></title></head>").title == "")
        #expect(head("<head><meta name=description content=x></head>").title == nil)
    }

    @Test func scriptsCommentsAndStylesHideWhatIsInThem() {
        let head = head("""
        <head>
        <script>var t = '<title>Script</title><meta property="og:title" content="no">';</script>
        <!-- <title>Comentario</title> -- <meta name="twitter:title" content="no"> -->
        <style>a::after { content: "<title>Estilo</title>" }</style>
        <noscript><meta property="og:image" content="/sin-js.png"></noscript>
        <svg><title>Icono</title></svg>
        <title>La buena</title>
        </head>
        """)

        #expect(head.title == "La buena")
        // Link Presentation runs no scripts, so what `<noscript>` holds counts.
        #expect(head.metas == [HTMLHead.Meta(property: "og:image", content: "/sin-js.png")])
    }

    @Test func malformedMarkupIsReadAsABrowserReadsIt() {
        let head = head("""
        <html><head>
        <title>2 < 3 & 4 > 1</title>
        <meta property="og:title" property="ignored" content="Primero" content="Segundo">
        <meta property=og:image content=/a.png/>
        <link rel=icon href= /i.png >
        <meta content="sin clave">
        <link href="/sin-rel.png">
        <p>texto <b>suelto</p>
        """)

        #expect(head.title == "2 < 3 & 4 > 1")
        #expect(head.metas == [
            HTMLHead.Meta(property: "og:title", content: "Primero"),
            HTMLHead.Meta(property: "og:image", content: "/a.png/"),
        ])
        #expect(head.links == [HTMLHead.Link(rel: "icon", href: "/i.png")])
    }

    @Test func aTitleThatNeverClosesRunsToTheEndOfWhatWasRead() {
        #expect(head("<head><title>Sin cerrar<meta property=og:image content=/a.png>").title == "Sin cerrar<meta property=og:image content=/a.png>")
    }

    @Test func withoutAnEndOfHeadTheWholePageIsRead() {
        let head = head("<html><body><title>En el cuerpo</title><meta property=og:title content=Tarde></body></html>")

        #expect(head.title == "En el cuerpo")
        #expect(head.metas.map(\.content) == ["Tarde"])
    }

    @Test func whatAHeadCannotHoldEndsItAsInABrowser() {
        let divided = head("""
        <head><title>T</title><link rel="icon" href="/a.png"><div id="contenido"></div>
        <link rel="icon" href="/b.png"><meta property="og:title" content="Después"></head>
        """)
        #expect(divided.links.map(\.isInHead) == [true, false])
        // Tags in the body are still read.
        #expect(divided.metas.map(\.content) == ["Después"])

        let text = head(#"<head><link rel="icon" href="/a.png"> texto <link rel="icon" href="/b.png"></head>"#)
        #expect(text.links.map(\.isInHead) == [true, false])

        let spaced = head("<head>\n  <script>var a = '<div>';</script>\n  <!-- <p> -->\n  <link rel=icon href=/a.png>\n</head>")
        #expect(spaced.links.map(\.isInHead) == [true])
    }

    @Test func aTitleAfterAnEmptyHeadIsStillFound() {
        // info.cern.ch: an empty head and the title in the body.
        let head = head("<html><head></head><body><header> <title>http://info.cern.ch</title> </header><meta property=og:image content=/x.png>")

        #expect(head.title == "http://info.cern.ch")
        #expect(head.metas.isEmpty)
    }

    @Test func readingStopsAtTheEndOfTheHeadOnlyWithATitle() {
        for (page, finished) in [
            ("<head><title>T</title></head><body>", true),
            ("<head><meta property=og:title content=T></head><body>", true),
            ("<head></head><body><p>sin título", false),
            ("<head></head><body><title>T</title>", true),
        ] {
            var scanner = HTMLHeadScanner()
            Array(page.utf8).withUnsafeBytes { scanner.scan($0, isComplete: false) }
            #expect(scanner.isFinished == finished, "\(page)")
        }
    }

    @Test func nothingAfterTheEndOfTheHeadIsRead() {
        let head = head("<head><title>Cabecera</title></head><body><meta property=og:title content=Cuerpo><title>Otro</title>")

        #expect(head.title == "Cabecera")
        #expect(head.metas.isEmpty)
    }

    // MARK: Character encoding

    @Test func theResponsesCharsetComesFirst() {
        let bytes = Data("<title>Caf\u{E9}</title><meta charset=utf-8>".data(using: .isoLatin1)!)

        #expect(HTMLHead(parsing: bytes, charset: "iso-8859-1").title == "Café")
    }

    @Test func thePagesOwnCharsetDeclarationIsUsed() {
        let declared = "<meta charset=\"windows-1252\"><title>Caf\u{E9} \u{201C}q\u{201D}</title>"
        #expect(HTMLHead(parsing: declared.data(using: .windowsCP1252)!, charset: nil).title == "Café “q”")

        // ISO-8859-15 has the euro sign where Latin-1 has "¤".
        var equivalent = Data("<meta http-equiv=\"Content-Type\" content=\"text/html; charset=ISO-8859-15\"><title>".utf8)
        equivalent.append(0xA4)
        equivalent.append(Data("</title>".utf8))
        #expect(HTMLHead(parsing: equivalent, charset: nil).title == "€")
    }

    @Test func undeclaredTextIsUTF8WhenItCanBeAndWindows1252WhenNot() {
        #expect(HTMLHead(parsing: Data("<title>Café</title>".utf8), charset: nil).title == "Café")
        #expect(HTMLHead(parsing: "<title>Caf\u{E9}</title>".data(using: .isoLatin1)!, charset: nil).title == "Café")
        // Bytes no encoding defines decode to something, not to nothing.
        #expect(HTMLHead(parsing: Data([0x3C, 0x74, 0x69, 0x74, 0x6C, 0x65, 0x3E, 0x81, 0x3C, 0x2F, 0x74, 0x69, 0x74, 0x6C, 0x65, 0x3E]), charset: "utf-8").title == "\u{FFFD}")
    }

    @Test func aByteOrderMarkDecidesTheEncoding() {
        var utf16 = Data([0xFF, 0xFE])
        utf16.append("<title>Ñandú</title><meta property=og:title content=Sí>".data(using: .utf16LittleEndian)!)

        let head = HTMLHead(parsing: utf16, charset: "iso-8859-1")

        #expect(head.title == "Ñandú")
        #expect(head.metas.map(\.content) == ["Sí"])
    }

    @Test func aCharsetIsReadFromAContentType() {
        #expect(HTMLHead.charset(inContentType: "text/html; charset=UTF-8") == "utf-8")
        #expect(HTMLHead.charset(inContentType: "text/html;charset=\"windows-1252\"") == "windows-1252")
        #expect(HTMLHead.charset(inContentType: "text/html") == nil)
    }

    // MARK: Reading as the page arrives

    @Test func readingInPiecesFindsWhatReadingAtOnceFinds() {
        let page = Array("""
        <html><head><!-- a > b --><title>Trozos</title><script>if (a</b) {}</script>
        <meta property="og:title" content="Por partes"><link rel=icon href="/i.png"></head><body>
        """.utf8)
        var whole = HTMLHeadScanner()
        page.withUnsafeBytes { whole.scan($0, isComplete: true) }

        for size in [1, 2, 3, 7, 16] {
            var scanner = HTMLHeadScanner()
            var received: [UInt8] = []
            for start in stride(from: 0, to: page.count, by: size) {
                received += page[start..<min(start + size, page.count)]
                received.withUnsafeBytes { scanner.scan($0, isComplete: false) }
            }
            #expect(scanner.title == whole.title)
            #expect(scanner.elements == whole.elements)
            #expect(scanner.hasReachedEndOfHead)
        }
    }

    @Test func theEndOfTheHeadIsNotTakenFromAScriptOrAComment() {
        var scanner = HTMLHeadScanner()
        let page = Array("<head><script>document.write('</head>')</script><!-- </head> -->".utf8)
        page.withUnsafeBytes { scanner.scan($0, isComplete: false) }

        #expect(!scanner.hasReachedEndOfHead)
    }
}
