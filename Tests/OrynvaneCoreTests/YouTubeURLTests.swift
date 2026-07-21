import XCTest
@testable import OrynvaneCore

final class YouTubeURLTests: XCTestCase {
    func testRecognizesYouTubeAddresses() {
        let addresses = [
            "https://youtube.com/",
            "https://www.youtube.com/watch?v=jNQXAC9IVRw",
            "https://m.youtube.com/shorts/jNQXAC9IVRw",
            "https://music.youtube.com/watch?v=jNQXAC9IVRw",
            "https://youtu.be/jNQXAC9IVRw?si=share",
            "https://www.youtube-nocookie.com/embed/jNQXAC9IVRw",
            "https://WWW.YOUTUBE.COM./live/jNQXAC9IVRw",
        ]

        for address in addresses {
            XCTAssertTrue(YouTubeURL.isYouTubeURL(URL(string: address)!), address)
        }
    }

    func testExtractsVideoIDFromSupportedYouTubeRoutes() {
        let addresses = [
            "https://www.youtube.com/watch?v=jNQXAC9IVRw&list=PL123&t=30",
            "https://youtu.be/jNQXAC9IVRw?si=share",
            "https://m.youtube.com/shorts/jNQXAC9IVRw",
            "https://youtube.com/live/jNQXAC9IVRw?feature=share",
            "https://www.youtube.com/embed/jNQXAC9IVRw",
            "https://www.youtube-nocookie.com/v/jNQXAC9IVRw",
        ]

        for address in addresses {
            XCTAssertEqual(
                YouTubeURL.videoID(from: URL(string: address)!),
                "jNQXAC9IVRw",
                address
            )
        }
    }

    func testDoesNotInventVideoIDForNonVideoYouTubePages() {
        let addresses = [
            "https://youtube.com/",
            "https://youtube.com/results?search_query=browser",
            "https://youtube.com/playlist?list=PL123",
            "https://youtube.com/results?v=jNQXAC9IVRw",
            "https://youtube.com/playlist?v=jNQXAC9IVRw&list=PL123",
            "https://studio.youtube.com/watch?v=jNQXAC9IVRw",
            "https://youtube.com/watch?v=too-short",
            "https://youtube.com/watch?v=bad!videoid",
            "https://youtu.be/",
        ]

        for address in addresses {
            XCTAssertNil(YouTubeURL.videoID(from: URL(string: address)!), address)
        }
    }

    func testExtractsVideoStartTime() {
        let addresses: [(String, TimeInterval)] = [
            ("https://youtube.com/watch?v=jNQXAC9IVRw&t=30", 30),
            ("https://youtu.be/jNQXAC9IVRw?t=1m30s", 90),
            ("https://youtube.com/embed/jNQXAC9IVRw?start=45", 45),
            ("https://youtube.com/watch?v=jNQXAC9IVRw#t=2m3s", 123),
            ("https://youtube.com/watch?v=jNQXAC9IVRw&t=invalid", 0),
        ]

        for (address, expected) in addresses {
            XCTAssertEqual(YouTubeURL.startTime(from: URL(string: address)!), expected, address)
        }
    }

    func testRejectsLookalikeHostsAndUnsupportedSchemes() {
        let addresses = [
            "https://notyoutube.com/watch?v=jNQXAC9IVRw",
            "https://youtube.com.evil.test/watch?v=jNQXAC9IVRw",
            "https://subdomain.youtu.be/jNQXAC9IVRw",
            "https://youtube.com@evil.test/watch?v=jNQXAC9IVRw",
            "https://.youtube.com/watch?v=jNQXAC9IVRw",
            "https://evil..youtube.com/watch?v=jNQXAC9IVRw",
            "https://youtube.com../watch?v=jNQXAC9IVRw",
            "https://youtubе.com/watch?v=jNQXAC9IVRw",
            "ftp://youtube.com/watch?v=jNQXAC9IVRw",
            "https:///watch?v=jNQXAC9IVRw",
            "/watch?v=jNQXAC9IVRw",
        ]

        for address in addresses {
            XCTAssertFalse(YouTubeURL.isYouTubeURL(URL(string: address)!), address)
            XCTAssertNil(YouTubeURL.videoID(from: URL(string: address)!), address)
        }
    }

    func testSchemelessShortLinkResolvesToVideo() {
        let url = URLResolver.address("youtu.be/jNQXAC9IVRw")

        XCTAssertEqual(url?.absoluteString, "https://youtu.be/jNQXAC9IVRw")
        XCTAssertEqual(url.flatMap(YouTubeURL.videoID(from:)), "jNQXAC9IVRw")
    }
}
