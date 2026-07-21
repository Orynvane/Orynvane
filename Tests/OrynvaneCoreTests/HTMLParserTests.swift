import XCTest
@testable import OrynvaneCore

final class HTMLParserTests: XCTestCase {
    func testParsesDocumentTitleAttributesEntitiesAndTraversal() {
        let document = HTMLParser().parse("""
            <!doctype html>
            <html><head><title>  Orynvane &amp; Friends  </title></head>
            <body><h1 id=hero hidden>Hello &#x1F30E;</h1><br>after</body></html>
            """)

        XCTAssertEqual(document.title, "Orynvane & Friends")
        XCTAssertEqual(document.documentElement?.name, "html")
        XCTAssertEqual(document.body?.name, "body")

        let heading = document.firstElement(named: "H1")
        XCTAssertEqual(heading?.attribute("ID"), "hero")
        XCTAssertTrue(heading?.hasAttribute("hidden") == true)
        XCTAssertEqual(heading?.textContent, "Hello 🌎")
        XCTAssertEqual(document.elements(named: "br").count, 1)
    }

    func testToleratesUnclosedAndMismatchedMarkup() {
        let document = HTMLParser().parse("<main><p>one<b>two</main><p>three")

        XCTAssertEqual(document.elements(named: "main").first?.textContent, "onetwo")
        XCTAssertEqual(document.elements(named: "p").map(\.textContent), ["onetwo", "three"])
        XCTAssertEqual(document.elements(named: "b").first?.textContent, "two")
    }

    func testScriptAndStyleContentsAreRawText() {
        let document = HTMLParser().parse("""
            <script>if (a < b) value = "&amp;";</script>
            <style>.note::after { content: "<b>"; }</style><p>safe</p>
            """)

        XCTAssertEqual(
            document.firstElement(named: "script")?.textContent,
            "if (a < b) value = \"&amp;\";"
        )
        XCTAssertEqual(
            document.firstElement(named: "style")?.textContent,
            ".note::after { content: \"<b>\"; }"
        )
        XCTAssertTrue(document.elements(named: "b").isEmpty)
        XCTAssertEqual(document.firstElement(named: "p")?.textContent, "safe")
    }

    func testTokenizerAndEntityDecoderHandleMalformedInput() {
        var tokenizer = HTMLTokenizer("<!-- open <div title='A &quot; B'>x &bogus; &#65;</div>")
        XCTAssertEqual(tokenizer.nextToken(), .comment(" open <div title='A &quot; B'>x &bogus; &#65;</div>"))
        XCTAssertNil(tokenizer.nextToken())

        XCTAssertEqual(HTMLEntities.decode("&lt;&gt; &#65; &#x42; &bogus;"), "<> A B &bogus;")
        XCTAssertEqual(HTMLEntities.decode("&#0; &#xD800;"), "� �")
    }

    func testCapsHostileElementNesting() {
        let source = String(repeating: "<div>", count: 2_000)
            + "still visible"
            + String(repeating: "</div>", count: 2_000)
        let document = HTMLParser().parse(source)

        XCTAssertTrue(document.children.first?.textContent.contains("still visible") == true)
    }
}
