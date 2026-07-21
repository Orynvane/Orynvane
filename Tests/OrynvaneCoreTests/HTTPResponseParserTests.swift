import Foundation
import XCTest
@testable import OrynvaneCore

final class HTTPResponseParserTests: XCTestCase {
    func testParsesContentLengthBodyAndNormalizesHeaderNames() throws {
        let response = wire(
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/plain\r\n" +
            "Content-Length: 5\r\n" +
            "\r\n" +
            "helloignored"
        )

        let parsed = try HTTPResponseParser.parse(response)

        XCTAssertEqual(parsed.statusCode, 200)
        XCTAssertEqual(parsed.reasonPhrase, "OK")
        XCTAssertEqual(parsed.headers["content-type"], "text/plain")
        XCTAssertEqual(parsed.body, Data("hello".utf8))
    }

    func testDecodesChunkedBodyAndConsumesTrailers() throws {
        let response = wire(
            "HTTP/1.1 200 OK\r\n" +
            "Transfer-Encoding: chunked\r\n" +
            "\r\n" +
            "4;example=yes\r\nWiki\r\n" +
            "5\r\npedia\r\n" +
            "0\r\nExpires: never\r\n\r\n"
        )

        let parsed = try HTTPResponseParser.parse(response)

        XCTAssertEqual(String(decoding: parsed.body, as: UTF8.self), "Wikipedia")
    }

    func testUsesConnectionCloseBodyWhenNoLengthIsPresent() throws {
        let response = wire(
            "HTTP/1.1 200 OK\r\n" +
            "Content-Type: text/html\r\n" +
            "\r\n" +
            "<h1>bare bones</h1>"
        )

        let parsed = try HTTPResponseParser.parse(response)

        XCTAssertEqual(String(decoding: parsed.body, as: UTF8.self), "<h1>bare bones</h1>")
    }

    func testSkipsInformationalResponse() throws {
        let response = wire(
            "HTTP/1.1 100 Continue\r\n\r\n" +
            "HTTP/1.1 204 No Content\r\n" +
            "X-Test: yes\r\n\r\n"
        )

        let parsed = try HTTPResponseParser.parse(response)

        XCTAssertEqual(parsed.statusCode, 204)
        XCTAssertEqual(parsed.reasonPhrase, "No Content")
        XCTAssertEqual(parsed.headers["x-test"], "yes")
        XCTAssertTrue(parsed.body.isEmpty)
    }

    func testRejectsTruncatedContentLengthBody() {
        let response = wire("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nabc")

        XCTAssertThrowsError(try HTTPResponseParser.parse(response)) { error in
            guard case HTTPClientError.invalidResponse = error else {
                return XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testRejectsMalformedChunk() {
        let response = wire(
            "HTTP/1.1 200 OK\r\n" +
            "Transfer-Encoding: chunked\r\n\r\n" +
            "nope\r\nbody\r\n0\r\n\r\n"
        )

        XCTAssertThrowsError(try HTTPResponseParser.parse(response))
    }

    func testDetectsCompleteExplicitlyFramedResponses() {
        let completeLength = wire("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhello")
        let incompleteLength = wire("HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nhell")
        let completeChunked = wire(
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" +
            "1\r\nx\r\n0\r\n\r\n"
        )

        XCTAssertTrue(HTTPResponseParser.isCompleteWithoutEOF(completeLength))
        XCTAssertFalse(HTTPResponseParser.isCompleteWithoutEOF(incompleteLength))
        XCTAssertTrue(HTTPResponseParser.isCompleteWithoutEOF(completeChunked))
    }

    func testConnectionCloseBodyStillWaitsForEOF() {
        let response = wire("HTTP/1.1 200 OK\r\n\r\npartial body")
        XCTAssertFalse(HTTPResponseParser.isCompleteWithoutEOF(response))
    }

    private func wire(_ text: String) -> Data {
        Data(text.utf8)
    }
}
