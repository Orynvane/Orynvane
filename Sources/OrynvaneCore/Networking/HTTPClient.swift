import Foundation
@preconcurrency import Network

/// The result of a single HTTP navigation after redirects have been followed.
public struct HTTPResponse: Sendable {
    public let statusCode: Int
    public let reasonPhrase: String

    /// HTTP field names are normalized to lowercase.
    public let headers: [String: String]

    public let body: Data
    public let finalURL: URL

    public init(
        statusCode: Int,
        reasonPhrase: String,
        headers: [String: String],
        body: Data,
        finalURL: URL
    ) {
        self.statusCode = statusCode
        self.reasonPhrase = reasonPhrase
        self.headers = headers
        self.body = body
        self.finalURL = finalURL
    }
}

public enum HTTPClientError: Error, Equatable, Sendable {
    case unsupportedScheme(String?)
    case missingHost
    case invalidPort(Int)
    case transport(String)
    case invalidResponse(String)
    case responseTooLarge(Int)
    case timedOut
    case cancelled
    case tooManyRedirects
}

extension HTTPClientError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .unsupportedScheme(let scheme):
            return "Unsupported URL scheme: \(scheme ?? "none")"
        case .missingHost:
            return "The URL has no host."
        case .invalidPort(let port):
            return "Invalid network port: \(port)"
        case .transport(let message):
            return "Network transport failed: \(message)"
        case .invalidResponse(let message):
            return "Invalid HTTP response: \(message)"
        case .responseTooLarge(let limit):
            return "The response exceeded the \(limit)-byte limit."
        case .timedOut:
            return "The request timed out."
        case .cancelled:
            return "The request was cancelled."
        case .tooManyRedirects:
            return "The HTTP redirect limit was exceeded."
        }
    }
}

/// A deliberately small HTTP/1.1 client built directly on TCP and TLS.
///
/// `HTTPClient` performs GET requests and the small JSON POSTs needed by native
/// services. It does not provide cookies, a cache, authentication, compression,
/// or any other browser service.
public struct HTTPClient: Sendable {
    public static let defaultMaximumResponseBytes = 8 * 1024 * 1024

    private let maxRedirects: Int
    private let userAgent: String
    private let maximumResponseBytes: Int

    public init(
        maxRedirects: Int = 5,
        userAgent: String = "Orynvane/0.1",
        maximumResponseBytes: Int = HTTPClient.defaultMaximumResponseBytes
    ) {
        self.maxRedirects = max(0, maxRedirects)
        self.userAgent = userAgent
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    public func fetch(_ url: URL) async throws -> HTTPResponse {
        try await request(url, jsonBody: nil, additionalHeaders: [:])
    }

    func postJSON(
        _ body: Data,
        to url: URL,
        additionalHeaders: [String: String] = [:]
    ) async throws -> HTTPResponse {
        try await request(url, jsonBody: body, additionalHeaders: additionalHeaders)
    }

    private func request(
        _ url: URL,
        jsonBody: Data?,
        additionalHeaders: [String: String]
    ) async throws -> HTTPResponse {
        var currentURL = url.absoluteURL
        var currentBody = jsonBody
        var currentHeaders = additionalHeaders

        for redirectCount in 0...maxRedirects {
            let request = try Request(
                currentURL,
                userAgent: userAgent,
                jsonBody: currentBody,
                additionalHeaders: currentHeaders
            )
            let wireData = try await NetworkExchange(
                host: request.host,
                port: request.port,
                usesTLS: request.usesTLS,
                maximumResponseBytes: maximumResponseBytes
            ).run(request: request.bytes)
            let parsed = try HTTPResponseParser.parse(wireData)

            let response = HTTPResponse(
                statusCode: parsed.statusCode,
                reasonPhrase: parsed.reasonPhrase,
                headers: parsed.headers,
                body: parsed.body,
                finalURL: currentURL
            )

            guard Self.redirectStatusCodes.contains(parsed.statusCode),
                  let location = parsed.headers["location"],
                  !location.isEmpty else {
                return response
            }

            guard redirectCount < maxRedirects else {
                throw HTTPClientError.tooManyRedirects
            }

            guard let redirectURL = URL(string: location, relativeTo: currentURL)?.absoluteURL else {
                throw HTTPClientError.invalidResponse("The redirect Location is not a valid URL.")
            }

            if currentURL.scheme?.lowercased() == "https" &&
                redirectURL.scheme?.lowercased() == "http" {
                throw HTTPClientError.invalidResponse("An HTTPS request cannot redirect to HTTP.")
            }

            let sameOrigin = Self.hasSameOrigin(currentURL, redirectURL)
            if currentBody != nil,
               (parsed.statusCode == 307 || parsed.statusCode == 308),
               !sameOrigin {
                throw HTTPClientError.invalidResponse(
                    "A JSON POST cannot be redirected to a different origin."
                )
            }

            if !sameOrigin {
                currentHeaders = [:]
            }

            if parsed.statusCode == 303 ||
                ((parsed.statusCode == 301 || parsed.statusCode == 302) && currentBody != nil) {
                currentBody = nil
            }
            currentURL = redirectURL
        }

        throw HTTPClientError.tooManyRedirects
    }

    private static let redirectStatusCodes: Set<Int> = [301, 302, 303, 307, 308]
}

private extension HTTPClient {
    struct Request {
        let host: String
        let port: NWEndpoint.Port
        let usesTLS: Bool
        let bytes: Data

        init(
            _ url: URL,
            userAgent: String,
            jsonBody: Data?,
            additionalHeaders: [String: String]
        ) throws {
            guard let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https" else {
                throw HTTPClientError.unsupportedScheme(url.scheme)
            }
            guard let host = url.host, !host.isEmpty else {
                throw HTTPClientError.missingHost
            }

            let defaultPort = scheme == "https" ? 443 : 80
            let portNumber = url.port ?? defaultPort
            guard let rawPort = UInt16(exactly: portNumber),
                  rawPort > 0,
                  let port = NWEndpoint.Port(rawValue: rawPort) else {
                throw HTTPClientError.invalidPort(portNumber)
            }

            let target = Self.requestTarget(for: url)
            let hostForHeader = host.contains(":") ? "[\(host)]" : host
            let explicitPort = url.port.map { ":\($0)" } ?? ""
            let safeUserAgent = userAgent
                .replacingOccurrences(of: "\r", with: " ")
                .replacingOccurrences(of: "\n", with: " ")
            var requestLines = [
                "\(jsonBody == nil ? "GET" : "POST") \(target) HTTP/1.1",
                "Host: \(hostForHeader)\(explicitPort)",
                "User-Agent: \(safeUserAgent)",
                jsonBody == nil
                    ? "Accept: text/html, application/xhtml+xml, text/plain, */*"
                    : "Accept: application/json",
                "Accept-Encoding: identity",
                "Connection: close",
            ]

            for (name, value) in additionalHeaders.sorted(by: { $0.key < $1.key }) {
                guard Self.isSafeHeaderName(name), Self.isSafeHeaderValue(value) else {
                    throw HTTPClientError.invalidResponse("An HTTP request header is invalid.")
                }
                requestLines.append("\(name): \(value)")
            }

            if let jsonBody {
                requestLines.append("Content-Type: application/json")
                requestLines.append("Content-Length: \(jsonBody.count)")
            }

            requestLines.append("")
            requestLines.append("")

            var requestData = Data(requestLines.joined(separator: "\r\n").utf8)
            if let jsonBody {
                requestData.append(jsonBody)
            }

            self.host = host
            self.port = port
            self.usesTLS = scheme == "https"
            self.bytes = requestData
        }

        private static func isSafeHeaderName(_ value: String) -> Bool {
            !value.isEmpty && value.unicodeScalars.allSatisfy { scalar in
                scalar.value > 32 && scalar.value < 127 && !"()<>@,;:\\\"/[]?={} ".unicodeScalars.contains(scalar)
            }
        }

        private static func isSafeHeaderValue(_ value: String) -> Bool {
            !value.contains("\r") && !value.contains("\n")
        }

        private static func requestTarget(for url: URL) -> String {
            guard let components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
                return "/"
            }

            let path = components.percentEncodedPath.isEmpty ? "/" : components.percentEncodedPath
            if let query = components.percentEncodedQuery {
                return "\(path)?\(query)"
            }
            return path
        }
    }
}

extension HTTPClient {
    static func hasSameOrigin(_ first: URL, _ second: URL) -> Bool {
        guard let firstScheme = first.scheme?.lowercased(),
              let secondScheme = second.scheme?.lowercased(),
              let firstHost = first.host?.lowercased(),
              let secondHost = second.host?.lowercased() else {
            return false
        }

        func effectivePort(for url: URL, scheme: String) -> Int? {
            if let port = url.port {
                return port
            }
            switch scheme {
            case "http": return 80
            case "https": return 443
            default: return nil
            }
        }

        return firstScheme == secondScheme &&
            firstHost == secondHost &&
            effectivePort(for: first, scheme: firstScheme) ==
                effectivePort(for: second, scheme: secondScheme)
    }

    static func makeParameters(usesTLS: Bool) -> NWParameters {
        let parameters: NWParameters
        if usesTLS {
            parameters = NWParameters(
                tls: NWProtocolTLS.Options(),
                tcp: NWProtocolTCP.Options()
            )
        } else {
            parameters = .tcp
        }

        // Requests use origin-form targets and this client does not implement
        // HTTP proxy protocol, so a transparently selected system proxy would
        // receive invalid request bytes.
        parameters.preferNoProxies = true
        return parameters
    }
}

struct HTTPResponseBuffer {
    let maximumBytes: Int
    private(set) var data = Data()

    init(maximumBytes: Int) {
        self.maximumBytes = max(0, maximumBytes)
    }

    mutating func append(_ chunk: Data) -> Bool {
        guard chunk.count <= maximumBytes - data.count else {
            return false
        }
        data.append(chunk)
        return true
    }
}

private final class NetworkExchange: @unchecked Sendable {
    private static let timeout: TimeInterval = 15

    private let connection: NWConnection
    private let queue = DispatchQueue(label: "Orynvane.HTTPConnection")
    private var continuation: CheckedContinuation<Data, Error>?
    private var timeoutWorkItem: DispatchWorkItem?
    private var responseBuffer: HTTPResponseBuffer
    private var didSendRequest = false
    private var didFinish = false

    init(host: String, port: NWEndpoint.Port, usesTLS: Bool, maximumResponseBytes: Int) {
        let parameters = HTTPClient.makeParameters(usesTLS: usesTLS)
        connection = NWConnection(host: NWEndpoint.Host(host), port: port, using: parameters)
        responseBuffer = HTTPResponseBuffer(maximumBytes: maximumResponseBytes)
    }

    func run(request: Data) async throws -> Data {
        try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                queue.async { [self] in
                    guard !self.didFinish else {
                        continuation.resume(throwing: HTTPClientError.cancelled)
                        return
                    }
                    self.continuation = continuation
                    self.start(request: request)
                }
            }
        }, onCancel: {
            self.queue.async { [self] in
                self.finish(.failure(.cancelled))
            }
        })
    }

    private func start(request: Data) {
        let timeoutWorkItem = DispatchWorkItem { [weak self] in
            self?.finish(.failure(.timedOut))
        }
        self.timeoutWorkItem = timeoutWorkItem
        queue.asyncAfter(deadline: .now() + Self.timeout, execute: timeoutWorkItem)

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }

            switch state {
            case .ready:
                self.send(request: request)
            case .failed(let error):
                self.finish(.failure(.transport(error.localizedDescription)))
            case .cancelled where !self.didFinish:
                self.finish(.failure(.transport("The connection was cancelled.")))
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func send(request: Data) {
        guard !didSendRequest else { return }
        didSendRequest = true

        connection.send(content: request, completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                self.finish(.failure(.transport(error.localizedDescription)))
            } else {
                self.receiveNextChunk()
            }
        })
    }

    private func receiveNextChunk() {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }

            if let data, !data.isEmpty {
                guard self.responseBuffer.append(data) else {
                    self.finish(.failure(.responseTooLarge(self.responseBuffer.maximumBytes)))
                    return
                }
            }

            if let error {
                self.finish(.failure(.transport(error.localizedDescription)))
            } else if HTTPResponseParser.isCompleteWithoutEOF(self.responseBuffer.data) {
                self.finish(.success(self.responseBuffer.data))
            } else if isComplete {
                self.finish(.success(self.responseBuffer.data))
            } else {
                self.receiveNextChunk()
            }
        }
    }

    private func finish(_ result: Result<Data, HTTPClientError>) {
        guard !didFinish else { return }
        didFinish = true
        timeoutWorkItem?.cancel()
        timeoutWorkItem = nil
        connection.stateUpdateHandler = nil
        connection.cancel()
        continuation?.resume(with: result)
        continuation = nil
    }
}
