import XCTest
@testable import OrynvaneCore

final class HTTPClientTests: XCTestCase {
    func testConnectionsDoNotUseUnsupportedSystemProxies() {
        XCTAssertTrue(HTTPClient.makeParameters(usesTLS: false).preferNoProxies)
        XCTAssertTrue(HTTPClient.makeParameters(usesTLS: true).preferNoProxies)
    }
}
