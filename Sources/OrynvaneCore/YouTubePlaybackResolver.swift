import Foundation

public struct YouTubePlayback: Sendable, Equatable {
    public let videoID: String
    public let title: String
    public let author: String?
    public let durationSeconds: Int?
    public let streamURL: URL
    public let qualityLabel: String
    public let isLive: Bool

    public init(
        videoID: String,
        title: String,
        author: String?,
        durationSeconds: Int?,
        streamURL: URL,
        qualityLabel: String,
        isLive: Bool
    ) {
        self.videoID = videoID
        self.title = title
        self.author = author
        self.durationSeconds = durationSeconds
        self.streamURL = streamURL
        self.qualityLabel = qualityLabel
        self.isLive = isLive
    }
}

public protocol YouTubeStreamResolving: Sendable {
    func resolve(_ url: URL) async throws -> YouTubePlayback
}

public enum YouTubePlaybackError: Error, Equatable, Sendable {
    case invalidVideoURL
    case requestFailed(Int)
    case invalidResponse
    case unavailable(String)
    case noPlayableStream
}

extension YouTubePlaybackError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidVideoURL:
            return "This address does not identify a YouTube video."
        case .requestFailed(let statusCode):
            return "YouTube returned HTTP \(statusCode) while resolving the video."
        case .invalidResponse:
            return "YouTube returned an invalid player response."
        case .unavailable(let reason):
            return reason.isEmpty ? "This YouTube video is unavailable." : reason
        case .noPlayableStream:
            return "YouTube did not provide a compatible combined video stream."
        }
    }
}

public struct YouTubePlaybackResolver: YouTubeStreamResolving {
    private static let clientVersion = "21.26.364"
    private static let endpoint = URL(
        string: "https://www.youtube.com/youtubei/v1/player?prettyPrint=false"
    )!

    private let client: HTTPClient

    public init(client: HTTPClient = HTTPClient(
        userAgent: "com.google.android.youtube/21.26.364 (Linux; U; Android 11) gzip"
    )) {
        self.client = client
    }

    public func resolve(_ url: URL) async throws -> YouTubePlayback {
        guard let videoID = YouTubeURL.videoID(from: url) else {
            throw YouTubePlaybackError.invalidVideoURL
        }

        let request = PlayerRequest(
            context: .init(
                client: .init(
                    clientName: "ANDROID",
                    clientVersion: Self.clientVersion,
                    androidSdkVersion: 30,
                    hl: "en",
                    gl: "US",
                    userAgent: "com.google.android.youtube/\(Self.clientVersion) (Linux; U; Android 11) gzip",
                    osName: "Android",
                    osVersion: "11"
                )
            ),
            videoID: videoID,
            contentCheckOk: true,
            racyCheckOk: true
        )

        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            throw YouTubePlaybackError.invalidResponse
        }

        let response = try await client.postJSON(
            body,
            to: Self.endpoint,
            additionalHeaders: [
                "X-YouTube-Client-Name": "3",
                "X-YouTube-Client-Version": Self.clientVersion,
            ]
        )

        guard (200..<300).contains(response.statusCode) else {
            throw YouTubePlaybackError.requestFailed(response.statusCode)
        }

        return try Self.decodePlayback(response.body, expectedVideoID: videoID)
    }

    static func decodePlayback(_ data: Data, expectedVideoID: String) throws -> YouTubePlayback {
        let response: PlayerResponse
        do {
            response = try JSONDecoder().decode(PlayerResponse.self, from: data)
        } catch {
            throw YouTubePlaybackError.invalidResponse
        }

        guard response.playabilityStatus.status == "OK" else {
            throw YouTubePlaybackError.unavailable(
                response.playabilityStatus.reason ?? "This YouTube video is unavailable."
            )
        }

        let details = response.videoDetails
        let videoID = details?.videoID ?? expectedVideoID
        let title = details?.title?.isEmpty == false ? details!.title! : "YouTube Video"
        let duration = details?.lengthSeconds.flatMap(Int.init)

        let isLive = details?.isLive == true

        if isLive,
           let hlsURL = response.streamingData?.hlsManifestURL,
           isTrustedMediaURL(hlsURL) {
            return YouTubePlayback(
                videoID: videoID,
                title: title,
                author: details?.author,
                durationSeconds: duration,
                streamURL: hlsURL,
                qualityLabel: "Auto",
                isLive: true
            )
        }

        let format = response.streamingData?.formats?
            .filter { format in
                guard let url = format.url, isDirectlyPlayableMediaURL(url) else { return false }
                let mimeType = format.mimeType.lowercased()
                return mimeType.hasPrefix("video/mp4") &&
                    mimeType.contains("avc1") &&
                    mimeType.contains("mp4a")
            }
            .max { first, second in
                let firstRank = (first.height ?? 0, first.bitrate ?? 0)
                let secondRank = (second.height ?? 0, second.bitrate ?? 0)
                return firstRank < secondRank
            }

        if let format, let streamURL = format.url {
            return YouTubePlayback(
                videoID: videoID,
                title: title,
                author: details?.author,
                durationSeconds: duration,
                streamURL: streamURL,
                qualityLabel: format.qualityLabel ?? "Standard",
                isLive: isLive
            )
        }

        if let hlsURL = response.streamingData?.hlsManifestURL,
           isTrustedMediaURL(hlsURL) {
            return YouTubePlayback(
                videoID: videoID,
                title: title,
                author: details?.author,
                durationSeconds: duration,
                streamURL: hlsURL,
                qualityLabel: "Auto",
                isLive: isLive
            )
        }

        throw YouTubePlaybackError.noPlayableStream
    }

    private static func isTrustedMediaURL(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased() else {
            return false
        }
        return host == "googlevideo.com" || host.hasSuffix(".googlevideo.com")
    }

    private static func isDirectlyPlayableMediaURL(_ url: URL) -> Bool {
        guard isTrustedMediaURL(url),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return false
        }
        return components.queryItems?.contains(where: { $0.name == "n" }) != true
    }
}

private extension YouTubePlaybackResolver {
    struct PlayerRequest: Encodable {
        let context: Context
        let videoID: String
        let contentCheckOk: Bool
        let racyCheckOk: Bool

        enum CodingKeys: String, CodingKey {
            case context
            case videoID = "videoId"
            case contentCheckOk
            case racyCheckOk
        }
    }

    struct Context: Encodable {
        let client: Client
    }

    struct Client: Encodable {
        let clientName: String
        let clientVersion: String
        let androidSdkVersion: Int
        let hl: String
        let gl: String
        let userAgent: String
        let osName: String
        let osVersion: String
    }

    struct PlayerResponse: Decodable {
        let playabilityStatus: PlayabilityStatus
        let streamingData: StreamingData?
        let videoDetails: VideoDetails?
    }

    struct PlayabilityStatus: Decodable {
        let status: String
        let reason: String?
    }

    struct StreamingData: Decodable {
        let formats: [Format]?
        let hlsManifestURL: URL?

        enum CodingKeys: String, CodingKey {
            case formats
            case hlsManifestURL = "hlsManifestUrl"
        }
    }

    struct Format: Decodable {
        let url: URL?
        let mimeType: String
        let bitrate: Int?
        let height: Int?
        let qualityLabel: String?
    }

    struct VideoDetails: Decodable {
        let videoID: String?
        let title: String?
        let author: String?
        let lengthSeconds: String?
        let isLive: Bool?
        let isLiveContent: Bool?

        enum CodingKeys: String, CodingKey {
            case videoID = "videoId"
            case title
            case author
            case lengthSeconds
            case isLive
            case isLiveContent
        }
    }
}
