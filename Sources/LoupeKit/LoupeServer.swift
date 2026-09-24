import Foundation
import LoupeCore

#if canImport(Darwin) && ((canImport(UIKit) && !os(watchOS)) || canImport(AppKit) || os(watchOS))
import Darwin

private enum LoupeSocketAddress {
    case ipv4(sockaddr_in)
    case ipv6(sockaddr_in6)

    var family: Int32 {
        switch self {
        case .ipv4:
            return AF_INET
        case .ipv6:
            return AF_INET6
        }
    }

    func withSockaddr<Result>(
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result
    ) rethrows -> Result {
        switch self {
        case var .ipv4(address):
            return try withUnsafePointer(to: &address) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    try body(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        case var .ipv6(address):
            return try withUnsafePointer(to: &address) { pointer in
                try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
                    try body(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in6>.size))
                }
            }
        }
    }
}

public final class LoupeServer: @unchecked Sendable {
    public static let defaultPort: UInt16 = 8765
    private static let maximumHeaderBytes = 16 * 1024
    private static let maximumBodyBytes = 4 * 1024 * 1024

    private let queue = DispatchQueue(label: "dev.loupe.server")
    private var socketFD: Int32 = -1

    public init() {}

    public func start(
        port: UInt16 = LoupeServer.defaultPort,
        bindHost: String = "127.0.0.1"
    ) throws {
        stop()

        let socketAddress = try Self.socketAddress(bindHost: bindHost, port: port)
        let fd = Darwin.socket(socketAddress.family, SOCK_STREAM, 0)
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
        var noSigPipe: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var readTimeout = timeval(tv_sec: 5, tv_usec: 0)
        var writeTimeout = timeval(tv_sec: 10, tv_usec: 0)
        Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
        Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &writeTimeout, socklen_t(MemoryLayout<timeval>.size))

        if socketAddress.family == AF_INET6 {
            var v6Only: Int32 = 0
            Darwin.setsockopt(
                fd,
                IPPROTO_IPV6,
                IPV6_V6ONLY,
                &v6Only,
                socklen_t(MemoryLayout<Int32>.size)
            )
        }

        let bindResult = socketAddress.withSockaddr { sockaddrPointer, length in
            Darwin.bind(fd, sockaddrPointer, length)
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

    private static func socketAddress(bindHost: String, port: UInt16) throws -> LoupeSocketAddress {
        if bindHost == "0.0.0.0" || bindHost.contains(":") {
            var address = sockaddr_in6()
            address.sin6_len = UInt8(MemoryLayout<sockaddr_in6>.size)
            address.sin6_family = sa_family_t(AF_INET6)
            address.sin6_port = port.bigEndian
            let host = bindHost == "0.0.0.0" ? "::" : bindHost
            guard inet_pton(AF_INET6, host, &address.sin6_addr) == 1 else {
                throw LoupeServerError.invalidBindHost(bindHost)
            }
            return .ipv6(address)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        guard inet_pton(AF_INET, bindHost, &address.sin_addr) == 1 else {
            throw LoupeServerError.invalidBindHost(bindHost)
        }
        return .ipv4(address)
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

        let request: HTTPRequest
        switch readHTTPRequest(from: clientFD) {
        case let .success(data):
            do { request = try HTTPRequest(data: data) }
            catch let error as HTTPRequestError {
                writeResponse(ResponsePayload(status: error.status, body: #"{"error":"invalid_request"}"#), to: clientFD)
                return
            } catch { return }
        case .failure:
            writeResponse(ResponsePayload(status: 400, body: #"{"error":"invalid_request"}"#), to: clientFD)
            return
        }
        let payload = responsePayload(for: request)
        writeResponse(payload, to: clientFD)
    }

    private func writeResponse(_ payload: ResponsePayload, to clientFD: Int32) {
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

    private func readHTTPRequest(from clientFD: Int32) -> Result<Data, HTTPRequestError> {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: Self.maximumHeaderBytes)

        while true {
            let bytesRead = Darwin.read(clientFD, &buffer, buffer.count)
            guard bytesRead > 0 else {
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

    private func contentLength(from headerText: String) throws -> Int {
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

    private func responsePayload(for request: HTTPRequest) -> ResponsePayload {
        if request.path == "/health" {
            return ResponsePayload(status: 200, body: #"{"status":"ok","name":"LoupeKit"}"#)
        }

        let box = ResponseBox()
        let semaphore = DispatchSemaphore(value: 0)
        var work: DispatchWorkItem!
        work = DispatchWorkItem {
            guard !work.isCancelled else { return }
            box.markStarted()
            MainActor.assumeIsolated {
                box.payload = self.response(for: request)
            }
            semaphore.signal()
        }
        DispatchQueue.main.async(execute: work)

        guard semaphore.wait(timeout: .now() + 10) == .success else {
            work.cancel()
            let code = box.started ? "main_actor_timeout_action_may_have_run" : "main_actor_timeout"
            return ResponsePayload(status: 503, body: #"{"error":"\#(code)"}"#)
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
                let state = LoupeRuntime.shared.runtimeState()
                let response = request.queryItems["includeLogs"] == "true"
                    ? state
                    : LoupeRuntimeState(identity: state.identity)
                let data = try makeLoupeJSONEncoder().encode(response)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("runtime_encoding_failed", error: error))
            }
        case "/status":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeRuntime.shared.runtimeStatus())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("status_encoding_failed", error: error))
            }
        case "/accessibility/actions":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeAgent().captureAccessibilityActionTree())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("accessibility_actions_encoding_failed", error: error))
            }
        case "/logs":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeRuntime.shared.runtimeLogs())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("logs_encoding_failed", error: error))
            }
        case "/network":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeRuntime.shared.runtimeNetworkEvents())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("network_encoding_failed", error: error))
            }
        case "/refs":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeRuntime.shared.runtimeReferenceEvidence())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("refs_encoding_failed", error: error))
            }
        case "/objects/classes":
            do {
                let data = try makeLoupeJSONEncoder().encode(
                    LoupeRuntime.shared.runtimeObjectClasses(
                        matching: request.queryItems["matching"],
                        limit: request.queryItems["limit"].flatMap(Int.init) ?? 100
                    )
                )
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("object_classes_encoding_failed", error: error))
            }
        case "/objects/describe":
            do {
                guard let className = request.queryItems["class"] else {
                    return ResponsePayload(status: 400, body: #"{"error":"missing_class"}"#)
                }
                let data = try makeLoupeJSONEncoder().encode(
                    try LoupeRuntime.shared.runtimeObjectDescription(className: className)
                )
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("object_description_failed", error: error))
            }
        case "/leaks":
            do {
                let aliveOnly = request.queryItems["alive"] == "true" || request.queryItems["aliveOnly"] == "true"
                let data = try makeLoupeJSONEncoder().encode(
                    LoupeRuntime.shared.runtimeLifetimeProbes(aliveOnly: aliveOnly)
                )
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("leaks_encoding_failed", error: error))
            }
        case "/environment":
            do {
                let response: LoupeEnvironmentMutationResponse
                if request.method == "POST" {
                    let mutation = try JSONDecoder().decode(LoupeEnvironmentMutationRequest.self, from: request.body)
                    response = try LoupeAgent().setEnvironment(mutation)
                } else {
                    response = LoupeAgent().currentEnvironment()
                }
                let data = try makeLoupeJSONEncoder().encode(response)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("environment_failed", error: error))
            }
        case "/state/defaults", "/state/flags":
            do {
                if request.method == "POST" {
                    let mutation = try JSONDecoder().decode(LoupeStateMutationRequest.self, from: request.body)
                    let data = try makeLoupeJSONEncoder().encode(LoupeAgent().setDefault(mutation))
                    return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
                }

                guard let key = request.queryItems["key"] else {
                    return ResponsePayload(status: 400, body: #"{"error":"missing_key"}"#)
                }
                let data = try makeLoupeJSONEncoder().encode(LoupeAgent().defaultsEntry(key: key))
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("state_failed", error: error))
            }
        case "/state/keychain":
            do {
                let data = try makeLoupeJSONEncoder().encode(LoupeAgent().keychainItems())
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("keychain_encoding_failed", error: error))
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
        case "/hit-test":
            do {
                let point = try point(from: request.queryItems)
                let data = try makeLoupeJSONEncoder().encode(LoupeAgent().hitTest(point: point))
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("hit_test_failed", error: error))
            }
        case "/responder-chain":
            do {
                guard let selector = selector(from: request.queryItems) else {
                    return ResponsePayload(status: 400, body: #"{"error":"missing_selector"}"#)
                }
                guard let report = LoupeAgent().responderChain(selector: selector) else {
                    return ResponsePayload(status: 404, body: #"{"error":"node_not_found"}"#)
                }
                let data = try makeLoupeJSONEncoder().encode(report)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch {
                return ResponsePayload(status: 500, body: errorBody("responder_chain_failed", error: error))
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
        case "/activate":
            guard request.method == "POST" else {
                return ResponsePayload(status: 405, body: #"{"error":"method_not_allowed"}"#)
            }
            do {
                let action = try JSONDecoder().decode(LoupeActivationRequest.self, from: request.body)
                let response = try LoupeAgent().activate(action)
                let data = try makeLoupeJSONEncoder().encode(response)
                return ResponsePayload(status: 200, body: String(decoding: data, as: UTF8.self))
            } catch let error as LoupeMutationError {
                return ResponsePayload(status: error.status, body: errorBody(error.code, message: error.message))
            } catch {
                return ResponsePayload(status: 400, body: errorBody("activation_failed", error: error))
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

    private func point(from queryItems: [String: String]) throws -> LoupePoint {
        if let point = queryItems["point"] {
            let parts = point.split(separator: ",")
            guard parts.count == 2,
                  let x = Double(parts[0]),
                  let y = Double(parts[1]) else {
                throw LoupeDiagnosticError(message: "Expected point as x,y")
            }
            return LoupePoint(x: x, y: y)
        }

        guard let rawX = queryItems["x"], let rawY = queryItems["y"],
              let x = Double(rawX), let y = Double(rawY) else {
            throw LoupeDiagnosticError(message: "Expected --point x,y or --x <n> --y <n>")
        }
        return LoupePoint(x: x, y: y)
    }
}

public enum LoupeServerError: Error, Equatable {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case invalidBindHost(String)
}

private final class ResponseBox: @unchecked Sendable {
    private let lock = NSLock()
    private var didStart = false
    var payload: ResponsePayload?
    var started: Bool { lock.lock(); defer { lock.unlock() }; return didStart }
    func markStarted() { lock.lock(); didStart = true; lock.unlock() }
}

private struct ResponsePayload: Sendable {
    var status: Int
    var body: String
}

private enum HTTPRequestError: Error {
    case malformed, headerTooLarge, bodyTooLarge, unsupportedTransferEncoding
    var status: Int { self == .headerTooLarge || self == .bodyTooLarge ? 413 : 400 }
}

private struct HTTPRequest: Sendable {
    var method: String
    var path: String
    var queryItems: [String: String]
    var body: Data

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
