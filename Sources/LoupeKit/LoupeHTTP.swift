import Foundation
import LoupeCore

#if canImport(Darwin) && ((canImport(UIKit) && !os(watchOS)) || canImport(AppKit) || os(watchOS))
import Darwin

enum LoupeHTTP {
    private static let maximumHeaderBytes = 16 * 1024
    private static let maximumBodyBytes = 4 * 1024 * 1024

    static func readRequest(
        from clientFD: Int32,
        deadlineNanoseconds: UInt64
    ) -> Result<Data, HTTPRequestError> {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: Self.maximumHeaderBytes)

        while true {
            guard setReadTimeout(clientFD, through: deadlineNanoseconds) else {
                return .failure(.deadlineExceeded)
            }
            let bytesRead = Darwin.read(clientFD, &buffer, buffer.count)
            guard bytesRead > 0 else {
                if DispatchTime.now().uptimeNanoseconds >= deadlineNanoseconds {
                    return .failure(.deadlineExceeded)
                }
                // SO_RCVTIMEO is expressed in microseconds and can expire just
                // before the nanosecond deadline. Keep reading until the shared
                // absolute deadline rather than misclassifying that as malformed.
                if bytesRead < 0, errno == EAGAIN || errno == EINTR {
                    continue
                }
                return .failure(.malformed)
            }
            data.append(buffer, count: Int(bytesRead))

            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
                if data.count > Self.maximumHeaderBytes { return .failure(.headerTooLarge) }
                continue
            }

            guard headerEnd.lowerBound <= Self.maximumHeaderBytes else { return .failure(.headerTooLarge) }

            let headerText = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
            let expectedBodyLength: Int
            do { expectedBodyLength = try contentLength(from: headerText) }
            catch let error as HTTPRequestError { return .failure(error) }
            catch { return .failure(.malformed) }
            let bodyStart = headerEnd.upperBound
            if data.count >= bodyStart + expectedBodyLength {
                return .success(data)
            }
        }
    }

    private static func setReadTimeout(_ fd: Int32, through deadlineNanoseconds: UInt64) -> Bool {
        let now = DispatchTime.now().uptimeNanoseconds
        guard deadlineNanoseconds > now else {
            return false
        }
        let remainingNanoseconds = deadlineNanoseconds - now
        var timeout = timeval(
            tv_sec: Int(remainingNanoseconds / 1_000_000_000),
            tv_usec: Int32((remainingNanoseconds % 1_000_000_000) / 1_000)
        )
        if timeout.tv_sec == 0, timeout.tv_usec == 0 {
            timeout.tv_usec = 1
        }
        Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        return true
    }

    private static func contentLength(from headerText: String) throws -> Int {
        var seen = Set<String>()
        var length = 0
        let lines = headerText.components(separatedBy: "\r\n")
        guard let requestLine = lines.first,
              requestLine.split(separator: " ", omittingEmptySubsequences: true).count == 3 else {
            throw HTTPRequestError.malformed
        }
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: ":"), separator != line.startIndex else { throw HTTPRequestError.malformed }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard seen.insert(key).inserted else { throw HTTPRequestError.malformed }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            if key == "transfer-encoding" { throw HTTPRequestError.unsupportedTransferEncoding }
            if key == "content-length" {
                guard let parsed = Int(value), parsed >= 0, parsed <= Self.maximumBodyBytes else { throw HTTPRequestError.bodyTooLarge }
                length = parsed
            }
        }
        return length
    }


}

struct ResponsePayload: Sendable {
    var status: Int
    var body: String
}

enum HTTPRequestError: Error {
    case malformed, headerTooLarge, bodyTooLarge, unsupportedTransferEncoding, deadlineExceeded
    var status: Int { self == .headerTooLarge || self == .bodyTooLarge ? 413 : 400 }
}

struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var queryItems: [String: String]
    var body: Data

    var mutatesRuntime: Bool {
        method == "POST" && [
            "/environment",
            "/state/defaults",
            "/state/flags",
            "/mutate",
            "/activate",
            "/constraint",
        ].contains(path)
    }

    init(data: Data) throws {
        let text = String(decoding: data, as: UTF8.self)
        let headerEnd = data.range(of: Data("\r\n\r\n".utf8))
        let headerText: String
        if let headerEnd {
            headerText = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
            body = Data(data[headerEnd.upperBound...])
        } else {
            headerText = text
            body = Data()
        }

        let headerLines = headerText.split(separator: "\r\n", omittingEmptySubsequences: false)
        let requestLine = headerLines.first ?? ""
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2].hasPrefix("HTTP/") else { throw HTTPRequestError.malformed }
        method = String(parts[0])
        let rawPath = String(parts[1])

        if let components = URLComponents(string: rawPath) {
            path = components.path
            let pairs = (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } }
            guard Set(pairs.map(\.0)).count == pairs.count else { throw HTTPRequestError.malformed }
            queryItems = Dictionary(uniqueKeysWithValues: pairs)
        } else {
            path = rawPath
            queryItems = [:]
            if let queryIndex = path.firstIndex(of: "?") {
                path = String(path[..<queryIndex])
            }
        }
    }
}

#endif
