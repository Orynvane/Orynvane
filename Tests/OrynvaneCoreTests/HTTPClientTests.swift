import Foundation
import XCTest
@testable import OrynvaneCore

final class HTTPClientTests: XCTestCase {
    func testConnectionsDoNotUseUnsupportedSystemProxies() {
        XCTAssertTrue(HTTPClient.makeParameters(usesTLS: false).preferNoProxies)
        XCTAssertTrue(HTTPClient.makeParameters(usesTLS: true).preferNoProxies)
    }

    func testRedirectOriginComparisonUsesSchemeHostAndEffectivePort() {
        XCTAssertTrue(HTTPClient.hasSameOrigin(
            URL(string: "https://example.com/path")!,
            URL(string: "https://EXAMPLE.com:443/elsewhere")!
        ))
        XCTAssertFalse(HTTPClient.hasSameOrigin(
            URL(string: "https://example.com/path")!,
            URL(string: "http://example.com/path")!
        ))
        XCTAssertFalse(HTTPClient.hasSameOrigin(
            URL(string: "https://example.com/path")!,
            URL(string: "https://example.com:8443/path")!
        ))
        XCTAssertFalse(HTTPClient.hasSameOrigin(
            URL(string: "https://example.com/path")!,
            URL(string: "https://other.example/path")!
        ))
    }

    func testDefaultResponseBufferAcceptsFourMiBPage() {
        var buffer = HTTPResponseBuffer(maximumBytes: HTTPClient.defaultMaximumResponseBytes)
        let page = Data(repeating: 0x61, count: 4 * 1024 * 1024)

        XCTAssertTrue(buffer.append(page))
        XCTAssertEqual(buffer.data.count, page.count)
    }

    func testResponseBufferRejectsDataBeyondLimitWithoutAppendingIt() {
        var buffer = HTTPResponseBuffer(maximumBytes: 4)

        XCTAssertTrue(buffer.append(Data([0, 1, 2, 3])))
        XCTAssertFalse(buffer.append(Data([4])))
        XCTAssertEqual(buffer.data, Data([0, 1, 2, 3]))
    }
}
