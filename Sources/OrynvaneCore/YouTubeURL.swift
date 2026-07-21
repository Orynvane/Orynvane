import Foundation

/// Recognizes YouTube addresses and extracts video identifiers without loading
/// a secondary browser engine.
public enum YouTubeURL {
    public static func isYouTubeURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = normalizedHost(of: url) else {
            return false
        }

        if host == "youtu.be" {
            return true
        }

        return videoDomains.contains { domain in
            host == domain || host.hasSuffix(".\(domain)")
        }
    }

    public static func videoID(from url: URL) -> String? {
        guard isYouTubeURL(url), let host = normalizedHost(of: url) else {
            return nil
        }

        if host == "youtu.be" {
            return validVideoID(url.pathComponents.dropFirst().first)
        }

        let path = url.pathComponents.filter { $0 != "/" }

        if playbackPageHosts.contains(host),
           path.count == 1,
           path[0].lowercased() == "watch",
           let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
           let queryID = components.queryItems?.first(where: { $0.name == "v" })?.value,
           let videoID = validVideoID(queryID) {
            return videoID
        }

        guard playbackPageHosts.contains(host),
              path.count >= 2,
              videoPathPrefixes.contains(path[0].lowercased()) else {
            return nil
        }

        return validVideoID(path[1])
    }

    /// Returns the starting offset carried by a recognized video link.
    public static func startTime(from url: URL) -> TimeInterval {
        guard videoID(from: url) != nil,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return 0
        }

        let queryNames = ["t", "start", "time_continue"]
        if let queryItems = components.queryItems {
            for name in queryNames {
                if let value = queryItems.first(where: { $0.name.lowercased() == name })?.value,
                   let seconds = parseTimestamp(value) {
                    return seconds
                }
            }
        }

        if let fragment = components.fragment,
           let fragmentComponents = URLComponents(string: "?" + fragment),
           let value = fragmentComponents.queryItems?
            .first(where: { $0.name.lowercased() == "t" })?.value,
           let seconds = parseTimestamp(value) {
            return seconds
        }

        return 0
    }

    private static func normalizedHost(of url: URL) -> String? {
        guard let rawHost = url.host?.lowercased() else { return nil }

        let host = rawHost.hasSuffix(".") ? String(rawHost.dropLast()) : rawHost
        guard !host.isEmpty,
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains("..") else {
            return nil
        }

        return host
    }

    private static func validVideoID(_ value: String?) -> String? {
        guard let value,
              value.utf8.count == 11,
              value.utf8.allSatisfy({ byte in
                  (byte >= 48 && byte <= 57) ||
                      (byte >= 65 && byte <= 90) ||
                      (byte >= 97 && byte <= 122) ||
                      byte == 45 || byte == 95
              }) else {
            return nil
        }

        return value
    }

    private static func parseTimestamp(_ value: String) -> TimeInterval? {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let seconds = TimeInterval(value), seconds.isFinite, seconds >= 0 {
            return seconds
        }

        var number = ""
        var total: TimeInterval = 0
        var foundUnit = false

        for character in value {
            if character.isNumber || (character == "." && !number.contains(".")) {
                number.append(character)
                continue
            }

            guard let amount = TimeInterval(number), amount.isFinite, amount >= 0 else {
                return nil
            }
            switch character {
            case "h": total += amount * 3_600
            case "m": total += amount * 60
            case "s": total += amount
            default: return nil
            }
            number = ""
            foundUnit = true
        }

        return foundUnit && number.isEmpty && total.isFinite ? total : nil
    }

    private static let videoDomains = [
        "youtube.com",
        "youtube-nocookie.com",
    ]

    private static let playbackPageHosts: Set<String> = [
        "youtube.com",
        "www.youtube.com",
        "m.youtube.com",
        "music.youtube.com",
        "youtube-nocookie.com",
        "www.youtube-nocookie.com",
    ]

    private static let videoPathPrefixes: Set<String> = ["embed", "live", "shorts", "v"]
}
