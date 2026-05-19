import Foundation
import LoupeCore

#if canImport(UIKit)
import Darwin
import UIKit

public final class LoupeServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 8765

    private let queue = DispatchQueue(label: "dev.loupe.server")
    private var socketFD: Int32 = -1

    public init() {}

    public func start(port: UInt16 = LoupeServer.defaultPort) throws {
        stop()

        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw LoupeServerError.socketFailed(errno)
        }

        var reuse: Int32 = 1
        Darwin.setsockopt(
            fd,
            SOL_SOCKET,
            SO_REUSEADDR,
            &reuse,
            socklen_t(MemoryLayout<Int32>.size)
        )

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))

        let bindResult = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                Darwin.bind(fd, sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            let error = errno
            Darwin.close(fd)
            throw LoupeServerError.bindFailed(error)
        }

        guard Darwin.listen(fd, 8) == 0 else {
            let error = errno
            Darwin.close(fd)
            throw LoupeServerError.listenFailed(error)
        }

        socketFD = fd
        Task { @MainActor in
            LoupeRuntime.shared.activateBridge()
        }
        queue.async { [weak self] in
            self?.acceptLoop(socketFD: fd)
        }
    }

    public func stop() {
        guard socketFD >= 0 else {
            return
        }

        Darwin.close(socketFD)
        socketFD = -1
    }

    private func acceptLoop(socketFD: Int32) {
        while true {
            let clientFD = Darwin.accept(socketFD, nil, nil)
            if clientFD < 0 {
                break
            }

            handleClient(clientFD)
        }
    }

    private func handleClient(_ clientFD: Int32) {
        defer {
            Darwin.close(clientFD)
        }

        guard let requestData = readHTTPRequest(from: clientFD) else {
            return
        }

        let request = HTTPRequest(data: requestData)
        let payload = responsePayload(for: request)
        let responseText = """
        HTTP/1.1 \(payload.status) \(reasonPhrase(for: payload.status))\r
        Content-Type: application/json; charset=utf-8\r
        Content-Length: \(payload.body.utf8.count)\r
        Connection: close\r
        \r
        \(payload.body)
        """
        write(Data(responseText.utf8), to: clientFD)
    }

    private func readHTTPRequest(from clientFD: Int32) -> Data? {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)

        while true {
            let bytesRead = Darwin.read(clientFD, &buffer, buffer.count)
            guard bytesRead > 0 else {
                return data.isEmpty ? nil : data
            }
            data.append(buffer, count: Int(bytesRead))

            guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else {
                continue
            }

            let headerText = String(decoding: data[..<headerEnd.lowerBound], as: UTF8.self)
            let contentLength = contentLength(from: headerText)
            let bodyStart = headerEnd.upperBound
            if data.count >= bodyStart + contentLength {
                return data
            }
        }
    }

    private func contentLength(from headerText: String) -> Int {
        for line in headerText.split(separator: "\r\n") {
            guard let separator = line.firstIndex(of: ":") else { continue }
            let key = line[..<separator].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard key == "content-length" else { continue }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespacesAndNewlines)
            return Int(value) ?? 0
        }
        return 0
    }

    private func responsePayload(for request: HTTPRequest) -> ResponsePayload {
        if request.path == "/health" {
            return ResponsePayload(status: 200, body: #"{"status":"ok","name":"LoupeKit"}"#)
        }

        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)

        DispatchQueue.main.async {
            MainActor.assumeIsolated {
                box.payload = self.response(for: request)
            }
            semaphore.signal()
        }

        guard semaphore.wait(timeout: .now() + 10) == .success else {
            return ResponsePayload(status: 503, body: #"{"error":"main_actor_timeout"}"#)
        }
        return box.payload ?? ResponsePayload(status: 500, body: #"{"error":"empty_response"}"#)
    }

    @MainActor
    private func response(for request: HTTPRequest) -> ResponsePayload {
        switch request.path {
        case "/health":
            return ResponsePayload(status: 200, body: #"{"status":"ok","name":"LoupeKit"}"#)
        case "/runtime":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeRuntime.shared.runtimeState())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("runtime_encoding_failed", error: error))
            }
        case "/logs":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeRuntime.shared.runtimeLogs())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("logs_encoding_failed", error: error))
            }
        case "/snapshot":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeAgent().captureSnapshot())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("snapshot_encoding_failed", error: error))
            }
        case "/accessibility":
            do {
                let tree = LoupeAgent().captureAccessibilityTree()
                let data = try makeLoupeJSONEncoder().encode(tree)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("accessibility_encoding_failed", error: error))
            }
        case "/inspect":
            do {
                let snapshot = LoupeAgent().captureSnapshot()
                guard let selector = selector(from: request.queryItems) else {
                    return ResponsePayload(status: 400, body: #"{"error":"missing_selector"}"#)
                }
                guard let inspection = LoupeSnapshotInspector.inspect(selector, in: snapshot) else {
                    return ResponsePayload(status: 404, body: #"{"error":"node_not_found"}"#)
                }
                let data = try makeLoupeJSONEncoder().encode(inspection)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("inspect_encoding_failed", error: error))
            }
        case "/subtree":
            do {
                let snapshot = LoupeAgent().captureSnapshot()
                guard let selector = selector(from: request.queryItems) else {
                    return ResponsePayload(status: 400, body: #"{"error":"missing_selector"}"#)
                }
                let depth = request.queryItems["depth"].flatMap(Int.init) ?? 2
                guard let subtree = LoupeSnapshotInspector.subtree(selector, in: snapshot, maxDepth: depth) else {
                    return ResponsePayload(status: 404, body: #"{"error":"node_not_found"}"#)
                }
                let data = try makeLoupeJSONEncoder().encode(subtree)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("subtree_encoding_failed", error: error))
            }
        case "/audit":
            do {
                let audit = LoupeLayoutAuditor.audit(LoupeAgent().captureSnapshot())
                let data = try makeLoupeJSONEncoder().encode(audit)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("audit_encoding_failed", error: error))
            }
        case "/observation":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeAgent().captureCompactObservation())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("observation_encoding_failed", error: error))
            }
        case "/mutations":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeAgent().mutationCapabilities())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("mutations_encoding_failed", error: error))
            }
        case "/mutate":
            guard request.method == "POST" else {
                return ResponsePayload(status: 405, body: #"{"error":"method_not_allowed"}"#)
            }
            do {
                let mutation = try JSONDecoder().decode(LoupeMutationRequest.self, from: request.body)
                let response = try LoupeAgent().mutate(mutation)
                let data = try makeLoupeJSONEncoder().encode(response)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch let error as LoupeMutationError {
                return ResponsePayload(status: error.status, body: errorBody(error.code, message: error.message))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("mutation_failed", error: error))
            }
        case "/constraint":
            guard request.method == "POST" else {
                return ResponsePayload(status: 405, body: #"{"error":"method_not_allowed"}"#)
            }
            do {
                let mutation = try JSONDecoder().decode(LoupeConstraintMutationRequest.self, from: request.body)
                let response = try LoupeAgent().mutateConstraint(mutation)
                let data = try makeLoupeJSONEncoder().encode(response)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch let error as LoupeMutationError {
                return ResponsePayload(status: error.status, body: errorBody(error.code, message: error.message))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("constraint_mutation_failed", error: error))
            }
        default:
            return ResponsePayload(status: 404, body: #"{"error":"not_found"}"#)
        }
    }

    private func write(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else {
                return
            }

            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(
                    fd,
                    baseAddress.advanced(by: written),
                    rawBuffer.count - written
                )

                if result <= 0 {
                    break
                }

                written += result
            }
        }
    }

    private func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200:
            return "OK"
        case 400:
            return "Bad Request"
        case 405:
            return "Method Not Allowed"
        case 404:
            return "Not Found"
        case 500:
            return "Internal Server Error"
        default:
            return "OK"
        }
    }

    private func errorBody(_ code: String, error: Error) -> String {
        let message = String(describing: error)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return #"{"error":""# + code + #"","message":""# + message + #""}"#
    }

    private func errorBody(_ code: String, message: String) -> String {
        let escaped = message
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
            .replacingOccurrences(of: "\n", with: "\\n")
        return #"{"error":""# + code + #"","message":""# + escaped + #""}"#
    }

    private func selector(from queryItems: [String: String]) -> LoupeSelector? {
        if let testID = queryItems["testID"] ?? queryItems["test-id"] {
            return .testID(testID)
        }
        if let ref = queryItems["ref"] {
            return .ref(ref)
        }
        if let text = queryItems["text"] {
            return .text(text, exact: false)
        }
        if let role = queryItems["role"] {
            return .role(role)
        }
        return nil
    }
}

public enum LoupeServerError: Error, Equatable {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
}

private final class ResponseBox: @unchecked Sendable {
    var payload: ResponsePayload?
}

private struct ResponsePayload: Sendable {
    var status: Int
    var body: String
}

private struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var queryItems: [String: String]
    var body: Data

    init(data: Data) {
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
        let parts = requestLine.split(separator: " ")
        method = parts.indices.contains(0) ? String(parts[0]) : "GET"
        let rawPath = parts.indices.contains(1) ? String(parts[1]) : "/"

        if let components = URLComponents(string: rawPath) {
            path = components.path
            queryItems = Dictionary(
                uniqueKeysWithValues: (components.queryItems ?? []).compactMap { item in
                    item.value.map { (item.name, $0) }
                }
            )
        } else {
            path = rawPath
            queryItems = [:]
            if let queryIndex = path.firstIndex(of: "?") {
                path = String(path[..<queryIndex])
            }
        }
    }
}

public struct LoupeMutationError: Error, Equatable {
    var status: Int
    var code: String
    var message: String

    init(status: Int = 400, code: String, message: String) {
        self.status = status
        self.code = code
        self.message = message
    }
}

#endif
