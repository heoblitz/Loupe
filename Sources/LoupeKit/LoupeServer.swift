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
    private static let maximumConcurrentRequests = 16
    private static let defaultRequestDeadlineNanoseconds: UInt64 = 10_000_000_000

    // Socket syscalls deliberately stay on GCD workers.  Dispatching a blocking
    // `read`, `accept`, or `write` from a Swift task would consume a cooperative
    // executor thread while a peer is idle.
    private let acceptQueue = DispatchQueue(label: "dev.loupe.server.accept")
    private let ioQueue = DispatchQueue(label: "dev.loupe.server.io", attributes: .concurrent)
    private let state = ServerState(maximumConcurrentRequests: maximumConcurrentRequests)
    private let lifecycleLock = NSLock()
    private let requestDeadlineNanoseconds: UInt64
    private let requestHandler = LoupeRequestHandler()

    public init() {
        requestDeadlineNanoseconds = Self.defaultRequestDeadlineNanoseconds
    }

    init(requestDeadlineNanoseconds: UInt64) {
        self.requestDeadlineNanoseconds = requestDeadlineNanoseconds
    }

    deinit {
        stop()
    }

    public func start(
        port: UInt16 = LoupeServer.defaultPort,
        bindHost: String = "127.0.0.1"
    ) throws {
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        stopLocked()

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
        let flags = Darwin.fcntl(fd, F_GETFL)
        guard flags >= 0, Darwin.fcntl(fd, F_SETFL, flags | O_NONBLOCK) == 0 else {
            let error = errno
            Darwin.close(fd)
            throw LoupeServerError.socketFailed(error)
        }

        let generation = state.installListeningSocket(fd)
        let state = state
        let ioQueue = ioQueue
        let requestHandler = requestHandler
        let deadlineNanoseconds = requestDeadlineNanoseconds
        Task { @MainActor in
            LoupeRuntime.shared.activateBridge()
        }
        acceptQueue.async {
            Self.acceptLoop(
                socketFD: fd,
                generation: generation,
                state: state,
                ioQueue: ioQueue,
                deadlineNanoseconds: deadlineNanoseconds,
                requestHandler: requestHandler
            )
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
        lifecycleLock.lock()
        defer { lifecycleLock.unlock() }
        stopLocked()
    }

    private func stopLocked() {
        let stopped = state.stop()
        if stopped.listeningSocket >= 0 {
            // The nonblocking accept loop rechecks state after at most a short
            // poll. Keep this descriptor open until that worker has drained, so
            // it can never accept through a reused fd after restart.
            Darwin.shutdown(stopped.listeningSocket, SHUT_RDWR)
            acceptQueue.sync {}
            Darwin.close(stopped.listeningSocket)
        }
        for connection in stopped.connections {
            connection.shutdown()
        }
    }

    private static func acceptLoop(
        socketFD: Int32,
        generation: UInt64,
        state: ServerState,
        ioQueue: DispatchQueue,
        deadlineNanoseconds: UInt64,
        requestHandler: LoupeRequestHandler
    ) {
        while state.isListening(socketFD, generation: generation) {
            let clientFD = Darwin.accept(socketFD, nil, nil)
            if clientFD < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    waitForIncomingConnection(on: socketFD)
                    continue
                }
                break
            }

            guard configureClientSocket(clientFD) else {
                Darwin.shutdown(clientFD, SHUT_RDWR)
                Darwin.close(clientFD)
                continue
            }
            guard let connection = state.admit(
                clientFD,
                generation: generation,
                deadlineNanoseconds: deadlineNanoseconds
            ) else {
                ioQueue.async {
                    Self.writeResponse(
                        ResponsePayload(status: 503, body: #"{"error":"server_busy"}"#),
                        to: clientFD
                    )
                    Darwin.shutdown(clientFD, SHUT_RDWR)
                    Darwin.close(clientFD)
                }
                continue
            }
            ioQueue.async {
                Self.readRequest(
                    from: connection,
                    state: state,
                    ioQueue: ioQueue,
                    requestHandler: requestHandler
                )
            }
        }
    }

    private static func readRequest(
        from connection: ClientConnection,
        state: ServerState,
        ioQueue: DispatchQueue,
        requestHandler: LoupeRequestHandler
    ) {
        let request: HTTPRequest
        switch LoupeHTTP.readRequest(from: connection.fileDescriptor, deadlineNanoseconds: connection.deadlineNanoseconds) {
        case let .success(data):
            do { request = try HTTPRequest(data: data) }
            catch let error as HTTPRequestError {
                finish(connection, with: ResponsePayload(status: error.status, body: #"{"error":"invalid_request"}"#), state: state, ioQueue: ioQueue)
                return
            } catch {
                finish(connection, with: ResponsePayload(status: 400, body: #"{"error":"invalid_request"}"#), state: state, ioQueue: ioQueue)
                return
            }
        case .failure(.deadlineExceeded):
            finish(connection, with: ResponsePayload(status: 503, body: #"{"error":"request_timeout"}"#), state: state, ioQueue: ioQueue)
            return
        case .failure:
            finish(connection, with: ResponsePayload(status: 400, body: #"{"error":"invalid_request"}"#), state: state, ioQueue: ioQueue)
            return
        }

        let task = Task { [weak connection] in
            guard let connection else { return }
            let payload = await requestHandler.responsePayload(for: request, deadlineNanoseconds: connection.deadlineNanoseconds)
            guard !Task.isCancelled else {
                finish(connection, with: ResponsePayload(status: 503, body: #"{"error":"request_cancelled"}"#), state: state, ioQueue: ioQueue)
                return
            }
            finish(connection, with: payload, state: state, ioQueue: ioQueue)
        }
        connection.setRequestTask(task)
    }

    private static func waitForIncomingConnection(on fd: Int32) {
        var descriptor = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        // Polling is confined to the dedicated GCD accept worker. Its bounded
        // wait lets stop drain the worker before the listener descriptor closes.
        _ = Darwin.poll(&descriptor, 1, 10)
    }

    private static func configureClientSocket(_ fd: Int32) -> Bool {
        // BSD can preserve O_NONBLOCK across accept. Request reads deliberately
        // use SO_RCVTIMEO, so accepted sockets must be restored to blocking mode.
        let flags = Darwin.fcntl(fd, F_GETFL)
        guard flags >= 0, Darwin.fcntl(fd, F_SETFL, flags & ~O_NONBLOCK) == 0 else {
            return false
        }
        var noSigPipe: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var readTimeout = timeval(tv_sec: 5, tv_usec: 0)
        var writeTimeout = timeval(tv_sec: 10, tv_usec: 0)
        Darwin.setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &readTimeout, socklen_t(MemoryLayout<timeval>.size))
        Darwin.setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &writeTimeout, socklen_t(MemoryLayout<timeval>.size))
        return true
    }

    private static func finish(
        _ connection: ClientConnection,
        with payload: ResponsePayload,
        state: ServerState,
        ioQueue: DispatchQueue
    ) {
        ioQueue.async { [connection] in
            Self.writeResponse(payload, to: connection.fileDescriptor)
            connection.close()
            state.release(connection)
        }
    }

    private static func writeResponse(_ payload: ResponsePayload, to clientFD: Int32) {
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

    private static func write(_ data: Data, to fd: Int32) {
        data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var written = 0
            while written < rawBuffer.count {
                let result = Darwin.write(fd, baseAddress.advanced(by: written), rawBuffer.count - written)
                if result <= 0 { break }
                written += result
            }
        }
    }

    private static func reasonPhrase(for status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        case 405: return "Method Not Allowed"
        case 413: return "Payload Too Large"
        case 500: return "Internal Server Error"
        case 503: return "Service Unavailable"
        default: return "OK"
        }
    }

}

public enum LoupeServerError: Error, Equatable {
    case socketFailed(Int32)
    case bindFailed(Int32)
    case listenFailed(Int32)
    case invalidBindHost(String)
}

/// Serializes ownership of the listening socket and limits in-flight requests.
/// Connections own their descriptors until their I/O worker closes them, so a
/// restart cannot accidentally close a descriptor that the OS has reused.
private final class ServerState: @unchecked Sendable {
    private let lock = NSLock()
    private let maximumConcurrentRequests: Int
    private var listeningSocket: Int32 = -1
    private var generation: UInt64 = 0
    private var connections: [ObjectIdentifier: ClientConnection] = [:]

    init(maximumConcurrentRequests: Int) {
        self.maximumConcurrentRequests = maximumConcurrentRequests
    }

    func installListeningSocket(_ fd: Int32) -> UInt64 {
        lock.lock()
        defer { lock.unlock() }
        generation &+= 1
        listeningSocket = fd
        return generation
    }

    func isListening(_ fd: Int32, generation expectedGeneration: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return listeningSocket == fd && generation == expectedGeneration
    }

    func admit(
        _ fd: Int32,
        generation expectedGeneration: UInt64,
        deadlineNanoseconds: UInt64
    ) -> ClientConnection? {
        lock.lock()
        defer { lock.unlock() }
        guard listeningSocket >= 0,
              generation == expectedGeneration,
              connections.count < maximumConcurrentRequests else {
            return nil
        }
        let connection = ClientConnection(fileDescriptor: fd, deadlineNanoseconds: deadlineNanoseconds)
        connections[ObjectIdentifier(connection)] = connection
        return connection
    }

    func release(_ connection: ClientConnection) {
        lock.lock()
        connections.removeValue(forKey: ObjectIdentifier(connection))
        lock.unlock()
    }

    func stop() -> (listeningSocket: Int32, connections: [ClientConnection]) {
        lock.lock()
        defer { lock.unlock() }
        let fd = listeningSocket
        listeningSocket = -1
        generation &+= 1
        let activeConnections = Array(connections.values)
        connections.removeAll()
        return (fd, activeConnections)
    }
}

private final class ClientConnection: @unchecked Sendable {
    private let lock = NSLock()
    private var fd: Int32
    private var requestTask: Task<Void, Never>?
    private var isShutdown = false
    let deadlineNanoseconds: UInt64

    init(fileDescriptor: Int32, deadlineNanoseconds: UInt64) {
        fd = fileDescriptor
        self.deadlineNanoseconds = DispatchTime.now().uptimeNanoseconds &+ deadlineNanoseconds
    }

    deinit {
        close()
    }

    var fileDescriptor: Int32 {
        lock.lock()
        defer { lock.unlock() }
        return fd
    }

    func setRequestTask(_ task: Task<Void, Never>) {
        lock.lock()
        requestTask = task
        let shouldCancel = isShutdown
        lock.unlock()
        if shouldCancel { task.cancel() }
    }

    func shutdown() {
        lock.lock()
        isShutdown = true
        let task = requestTask
        // Keep shutdown under the ownership lock that close also claims.
        // Closing an fd after copying it could otherwise close an unrelated fd
        // if the kernel reuses the number between unlock and shutdown.
        if fd >= 0 {
            Darwin.shutdown(fd, SHUT_RDWR)
        }
        lock.unlock()
        task?.cancel()
    }

    func close() {
        lock.lock()
        let fd = self.fd
        self.fd = -1
        requestTask = nil
        lock.unlock()
        if fd >= 0 {
            Darwin.close(fd)
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
