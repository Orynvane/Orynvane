import Foundation

struct ParsedHTTPResponse: Equatable, Sendable {
    let statusCode: Int
    let reasonPhrase: String
    let headers: [String: String]
    let body: Data
}

enum HTTPResponseParser {
    static func parse(_ data: Data) throws -> ParsedHTTPResponse {
        let bytes = Array(data)
        var messageStart = 0

        while true {
            guard let headerEnd = firstIndex(of: [13, 10, 13, 10], in: bytes, startingAt: messageStart) else {
                throw invalid("The header terminator is missing.")
            }

            let headerBytes = bytes[messageStart..<headerEnd]
            guard let headerText = String(bytes: headerBytes, encoding: .isoLatin1) else {
                throw invalid("The response headers are not ISO-8859-1 text.")
            }

            var lines = headerText.components(separatedBy: "\r\n")
            guard !lines.isEmpty else {
                throw invalid("The status line is missing.")
            }

            let status = try parseStatusLine(lines.removeFirst())
            let headers = try parseHeaders(lines)
            let bodyStart = headerEnd + 4

            // Servers may send informational responses before the final one.
            if (100...199).contains(status.code), status.code != 101 {
                messageStart = bodyStart
                continue
            }

            let body: Data
            if status.code == 101 || status.code == 204 || status.code == 304 {
                body = Data()
            } else if isChunked(headers["transfer-encoding"]) {
                body = try decodeChunkedBody(bytes, startingAt: bodyStart)
            } else if let contentLength = try contentLength(from: headers["content-length"]) {
                guard bytes.count - bodyStart >= contentLength else {
                    throw invalid("The body is shorter than Content-Length.")
                }
                body = Data(bytes[bodyStart..<(bodyStart + contentLength)])
            } else {
                // With no explicit framing, the body ends when the connection closes.
                body = Data(bytes[bodyStart...])
            }

            return ParsedHTTPResponse(
                statusCode: status.code,
                reasonPhrase: status.reason,
                headers: headers,
                body: body
            )
        }
    }

    /// Returns true when response framing proves that the complete message is
    /// already buffered, so the transport need not wait for the peer to close.
    static func isCompleteWithoutEOF(_ data: Data) -> Bool {
        let bytes = Array(data)
        var messageStart = 0

        do {
            while true {
                guard let headerEnd = firstIndex(
                    of: [13, 10, 13, 10],
                    in: bytes,
                    startingAt: messageStart
                ) else {
                    return false
                }

                let headerBytes = bytes[messageStart..<headerEnd]
                guard let headerText = String(bytes: headerBytes, encoding: .isoLatin1) else {
                    return false
                }

                var lines = headerText.components(separatedBy: "\r\n")
                guard !lines.isEmpty else { return false }
                let status = try parseStatusLine(lines.removeFirst())
                let headers = try parseHeaders(lines)
                let bodyStart = headerEnd + 4

                if (100...199).contains(status.code), status.code != 101 {
                    messageStart = bodyStart
                    continue
                }

                if status.code == 101 || status.code == 204 || status.code == 304 {
                    return true
                }
                if isChunked(headers["transfer-encoding"]) {
                    _ = try decodeChunkedBody(bytes, startingAt: bodyStart)
                    return true
                }
                if let length = try contentLength(from: headers["content-length"]) {
                    return bytes.count - bodyStart >= length
                }
                return false
            }
        } catch {
            return false
        }
    }
}

private extension HTTPResponseParser {
    struct StatusLine {
        let code: Int
        let reason: String
    }

    static func parseStatusLine(_ line: String) throws -> StatusLine {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
        guard parts.count >= 2, parts[0].hasPrefix("HTTP/"), let code = Int(parts[1]), (100...999).contains(code) else {
            throw invalid("The status line is malformed.")
        }
        return StatusLine(code: code, reason: parts.count == 3 ? String(parts[2]) : "")
    }

    static func parseHeaders(_ lines: [String]) throws -> [String: String] {
        var headers: [String: String] = [:]

        for line in lines {
            guard let colon = line.firstIndex(of: ":") else {
                throw invalid("A header field is malformed.")
            }

            let name = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            guard !name.isEmpty else {
                throw invalid("A header field has no name.")
            }
            let valueStart = line.index(after: colon)
            let value = line[valueStart...].trimmingCharacters(in: .whitespaces)

            if let existing = headers[name] {
                headers[name] = "\(existing), \(value)"
            } else {
                headers[name] = value
            }
        }

        return headers
    }

    static func isChunked(_ transferEncoding: String?) -> Bool {
        transferEncoding?
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
            .contains("chunked") == true
    }

    static func contentLength(from value: String?) throws -> Int? {
        guard let value else { return nil }

        let values = value.split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard let firstText = values.first,
              let first = Int(firstText),
              first >= 0,
              values.allSatisfy({ Int($0) == first }) else {
            throw invalid("Content-Length is invalid or ambiguous.")
        }
        return first
    }

    static func decodeChunkedBody(_ bytes: [UInt8], startingAt start: Int) throws -> Data {
        var cursor = start
        var body = Data()

        while true {
            let sizeLine = try readLine(bytes, cursor: &cursor)
            let sizeText = sizeLine
                .split(separator: ";", maxSplits: 1, omittingEmptySubsequences: false)[0]
                .trimmingCharacters(in: .whitespaces)
            guard !sizeText.isEmpty, let size = UInt64(sizeText, radix: 16), size <= Int.max else {
                throw invalid("A chunk size is invalid.")
            }

            let chunkSize = Int(size)
            if chunkSize == 0 {
                // Consume optional trailer fields and their final empty line.
                while true {
                    let trailer = try readLine(bytes, cursor: &cursor)
                    if trailer.isEmpty { return body }
                    guard trailer.contains(":") else {
                        throw invalid("A chunk trailer is malformed.")
                    }
                }
            }

            guard chunkSize <= bytes.count - cursor else {
                throw invalid("A chunk is shorter than its declared size.")
            }
            body.append(contentsOf: bytes[cursor..<(cursor + chunkSize)])
            cursor += chunkSize

            guard cursor + 1 < bytes.count, bytes[cursor] == 13, bytes[cursor + 1] == 10 else {
                throw invalid("A chunk is missing its terminating CRLF.")
            }
            cursor += 2
        }
    }

    static func readLine(_ bytes: [UInt8], cursor: inout Int) throws -> String {
        guard let end = firstIndex(of: [13, 10], in: bytes, startingAt: cursor) else {
            throw invalid("A chunk line is incomplete.")
        }
        let text = String(decoding: bytes[cursor..<end], as: UTF8.self)
        cursor = end + 2
        return text
    }

    static func firstIndex(of pattern: [UInt8], in bytes: [UInt8], startingAt start: Int) -> Int? {
        guard !pattern.isEmpty, start >= 0, start <= bytes.count, pattern.count <= bytes.count - start else {
            return nil
        }

        for index in start...(bytes.count - pattern.count) where bytes[index..<(index + pattern.count)].elementsEqual(pattern) {
            return index
        }
        return nil
    }

    static func invalid(_ message: String) -> HTTPClientError {
        .invalidResponse(message)
    }
}
