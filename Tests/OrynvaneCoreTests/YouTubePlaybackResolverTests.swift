import Foundation
import XCTest
@testable import OrynvaneCore

final class YouTubePlaybackResolverTests: XCTestCase {
    func testSelectsHighestCombinedMP4FromPlayerResponse() throws {
        let data = Data(
            """
            {
              "playabilityStatus": {"status": "OK"},
              "videoDetails": {
                "videoId": "jNQXAC9IVRw",
                "title": "Me at the zoo",
                "author": "jawed",
                "lengthSeconds": "19",
                "isLive": false,
                "isLiveContent": true
              },
              "streamingData": {
                "formats": [
                  {
                    "url": "https://media.googlevideo.com/videoplayback?itag=18",
                    "mimeType": "video/mp4; codecs=\\"avc1.42001E, mp4a.40.2\\"",
                    "bitrate": 250000,
                    "height": 240,
                    "qualityLabel": "240p"
                  },
                  {
                    "url": "https://media.googlevideo.com/videoplayback?itag=22",
                    "mimeType": "video/mp4; codecs=\\"avc1.64001F, mp4a.40.2\\"",
                    "bitrate": 900000,
                    "height": 720,
                    "qualityLabel": "720p"
                  },
                  {
                    "url": "https://evil.example/video.mp4",
                    "mimeType": "video/mp4; codecs=\\"avc1.64001F, mp4a.40.2\\"",
                    "bitrate": 2000000,
                    "height": 1080,
                    "qualityLabel": "1080p"
                  }
                ]
              }
            }
            """.utf8
        )

        let playback = try YouTubePlaybackResolver.decodePlayback(
            data,
            expectedVideoID: "jNQXAC9IVRw"
        )

        XCTAssertEqual(playback.videoID, "jNQXAC9IVRw")
        XCTAssertEqual(playback.title, "Me at the zoo")
        XCTAssertEqual(playback.author, "jawed")
        XCTAssertEqual(playback.durationSeconds, 19)
        XCTAssertEqual(playback.qualityLabel, "720p")
        XCTAssertEqual(playback.streamURL.host, "media.googlevideo.com")
        XCTAssertFalse(playback.isLive)
    }

    func testPrefersHLSForLiveVideo() throws {
        let data = Data(
            """
            {
              "playabilityStatus": {"status": "OK"},
              "videoDetails": {
                "videoId": "awQzjn72bI0",
                "title": "NASA Live",
                "isLive": true,
                "isLiveContent": true
              },
              "streamingData": {
                "hlsManifestUrl": "https://manifest.googlevideo.com/api/manifest/hls_variant/live.m3u8",
                "formats": [
                  {
                    "url": "https://media.googlevideo.com/videoplayback?itag=18",
                    "mimeType": "video/mp4; codecs=\\"avc1.42001E, mp4a.40.2\\"",
                    "height": 360,
                    "qualityLabel": "360p"
                  }
                ]
              }
            }
            """.utf8
        )

        let playback = try YouTubePlaybackResolver.decodePlayback(
            data,
            expectedVideoID: "awQzjn72bI0"
        )

        XCTAssertTrue(playback.isLive)
        XCTAssertEqual(playback.qualityLabel, "Auto")
        XCTAssertEqual(playback.streamURL.host, "manifest.googlevideo.com")
    }

    func testSurfacesYouTubePlayabilityReason() {
        let data = Data(
            """
            {
              "playabilityStatus": {
                "status": "LOGIN_REQUIRED",
                "reason": "Sign in to confirm your age"
              }
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try YouTubePlaybackResolver.decodePlayback(data, expectedVideoID: "jNQXAC9IVRw")
        ) { error in
            XCTAssertEqual(
                error as? YouTubePlaybackError,
                .unavailable("Sign in to confirm your age")
            )
        }
    }

    func testRejectsResponsesWithoutCompatibleMedia() {
        let data = Data(
            """
            {
              "playabilityStatus": {"status": "OK"},
              "streamingData": {
                "formats": [
                  {
                    "url": "https://media.googlevideo.com/video-only",
                    "mimeType": "video/mp4; codecs=\\"avc1.64001F\\"",
                    "height": 1080,
                    "qualityLabel": "1080p"
                  }
                ]
              }
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try YouTubePlaybackResolver.decodePlayback(data, expectedVideoID: "jNQXAC9IVRw")
        ) { error in
            XCTAssertEqual(error as? YouTubePlaybackError, .noPlayableStream)
        }
    }

    func testRejectsStreamsThatNeedPlayerTokenTransformation() {
        let data = Data(
            """
            {
              "playabilityStatus": {"status": "OK"},
              "streamingData": {
                "formats": [
                  {
                    "url": "https://media.googlevideo.com/videoplayback?itag=18&n=encrypted",
                    "mimeType": "video/mp4; codecs=\\"avc1.42001E, mp4a.40.2\\"",
                    "height": 360,
                    "qualityLabel": "360p"
                  }
                ]
              }
            }
            """.utf8
        )

        XCTAssertThrowsError(
            try YouTubePlaybackResolver.decodePlayback(data, expectedVideoID: "jNQXAC9IVRw")
        ) { error in
            XCTAssertEqual(error as? YouTubePlaybackError, .noPlayableStream)
        }
    }
}
