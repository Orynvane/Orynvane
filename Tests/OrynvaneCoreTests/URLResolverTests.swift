import XCTest
@testable import OrynvaneCore

final class URLResolverTests: XCTestCase {
    func testAddressAddsHTTPS() {
        XCTAssertEqual(
            URLResolver.address("example.com/path")?.absoluteString,
            "https://example.com/path"
        )
    }

    func testAddressPreservesHTTP() {
        XCTAssertEqual(
            URLResolver.address(" http://example.com/ ")?.absoluteString,
            "http://example.com/"
        )
    }

    func testLinkResolvesRelativeToPage() {
        let base = URL(string: "https://example.com/one/index.html")!
        XCTAssertEqual(
            URLResolver.link("../two", relativeTo: base)?.absoluteString,
            "https://example.com/two"
        )
    }

    func testRejectsUnsupportedLinkScheme() {
        let base = URL(string: "https://example.com/")!
        XCTAssertNil(URLResolver.link("javascript:alert(1)", relativeTo: base))
    }
}
