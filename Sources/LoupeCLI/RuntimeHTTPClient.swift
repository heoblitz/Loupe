import Foundation
import LoupeCLIModel

private func loupeProbeHTTP(_ value: String) {
    guard ProcessInfo.processInfo.environment["LOUPE_HTTP_PROBE"] == "1" else { return }
    FileHandle.standardError.write(Data("\(Date().timeIntervalSince1970) \(value)\n".utf8))
}

/// Owns HTTP deadlines and transport failures; commands own endpoint semantics.
struct RuntimeHTTPClient: Sendable {
    static let shared = RuntimeHTTPClient()
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func data(
        from url: URL,
        timeout: TimeInterval,
        label: String
    ) async throws -> (Data, URLResponse) {
        var request = URLRequest(url: url)
        request.timeoutInterval = timeout
        return try await data(for: request, timeout: timeout, label: label)
    }

    func data(
        for request: URLRequest,
        timeout: TimeInterval,
        label: String
    ) async throws -> (Data, URLResponse) {
        var request = request
        request.timeoutInterval = timeout
        let timedRequest = request
        let requestURL = request.url?.absoluteString ?? "unknown-url"
        #if os(macOS)
        let activity = ProcessInfo.processInfo.environment["LOUPE_HTTP_ACTIVITY_PROBE"] == "1"
            ? ProcessInfo.processInfo.beginActivity(options: .userInitiatedAllowingIdleSystemSleep, reason: "Inspect requested runtime") : nil
        defer { if let activity { ProcessInfo.processInfo.endActivity(activity) } }
        #endif
        loupeProbeHTTP("request begin " + requestURL)
        do {
            return try await Self.withExplicitTimeout(seconds: timeout) { [session] in
                loupeProbeHTTP("URLSession begin")
                let result = try await session.data(for: timedRequest)
                loupeProbeHTTP("URLSession done bytes=\(result.0.count)")
                return result
            }
        } catch {
            loupeProbeHTTP("request error: \(error)")
            let detail = (error as? CLIError)?.description ?? error.localizedDescription
            let method = (request.httpMethod ?? "GET").uppercased()
            let guidance = ["GET", "HEAD", "OPTIONS"].contains(method) ? ""
                : " The action may already have run. Inspect fresh runtime state before retrying."
            throw CLIError("\(label) timed out or failed for \(requestURL): \(detail)\(guidance)")
        }
    }

    private static func withExplicitTimeout<Value: Sendable>(
        seconds: TimeInterval,
        operation: @escaping @Sendable () async throws -> Value
    ) async throws -> Value {
        try await withThrowingTaskGroup(of: Value.self) { group in
            group.addTask {
                try await operation()
            }
            group.addTask {
                loupeProbeHTTP("timer begin \(seconds)")
                try await Task.sleep(nanoseconds: timeoutNanoseconds(seconds))
                loupeProbeHTTP("timer fired")
                throw CLIError("request timed out after \(seconds)s")
            }

            defer {
                group.cancelAll()
            }

            guard let value = try await group.next() else {
                throw CLIError("request timed out after \(seconds)s")
            }
            return value
        }
    }

    private static func timeoutNanoseconds(_ seconds: TimeInterval) -> UInt64 {
        let capped = min(max(seconds, 0), Double(UInt64.max) / 1_000_000_000)
        return UInt64((capped * 1_000_000_000).rounded(.up))
    }

}
