import Foundation
import ImageIO
import Darwin
import LoupeCLIModel
import LoupeHID

/// Native capture avoids a simctl lifecycle per frame. Publish only complete,
/// fresh bytes within the deadline; reap children used by the API fallback.
enum SimulatorScreenshotCapture {
    enum Frame: Sendable { case png(Data), unsupported }

    // A native proxy can block independently of the guest. Only the caller
    // publishes bytes; an expired worker cannot write or replace any file.
    private final class Completion: @unchecked Sendable {
        let signal = DispatchSemaphore(value: 0)
        private let lock = NSLock()
        private var open = true
        private var result: Result<Frame, Error>?

        func finish(_ result: Result<Frame, Error>) {
            lock.lock()
            if open { self.result = result }
            lock.unlock()
            signal.signal()
        }

        func take() -> Result<Frame, Error>? {
            lock.lock()
            defer { lock.unlock() }
            open = false
            defer { result = nil }
            return result
        }
    }

    static func nativeFrame(
        timeout: TimeInterval, read: @escaping @Sendable () throws -> Frame
    ) throws -> Frame {
        let completion = Completion()
        let deadline = DispatchTime.now() + timeout
        DispatchQueue.global(qos: .userInteractive).async {
            completion.finish(Result { try read() })
        }
        guard completion.signal.wait(timeout: deadline) == .success,
              DispatchTime.now() < deadline, let result = completion.take() else {
            _ = completion.take()
            throw CLIError("Simulator framebuffer capture timed out after \(timeout)s")
        }
        return try result.get()
    }

    static func capture(udid: String, outputURL: URL, timeout: TimeInterval = 10) throws {
        let started = DispatchTime.now().uptimeNanoseconds
        let frame = try nativeFrame(timeout: timeout) {
            var bytes: UnsafeMutableRawPointer?
            var count = 0
            var message: UnsafeMutablePointer<CChar>?
            let status = LoupeSimulatorCopyPNG(udid, &bytes, &count, &message)
            defer {
                if let bytes { LoupeSimulatorFreeBuffer(bytes) }
                if let message { LoupeHIDFreeCString(message) }
            }
            if status == 2 { return .unsupported }
            guard status == 0, let bytes, count > 0 else {
                throw CLIError(message.map { String(cString: $0) } ?? "Could not capture simulator framebuffer")
            }
            return .png(Data(bytes: bytes, count: count))
        }
        switch frame {
        case .png(let data):
            try publish(data, to: outputURL)
            // Do not retain stderr from a previous simctl capture.
            try Data().write(to: outputURL.appendingPathExtension("stderr.log"), options: .atomic)
        case .unsupported:
            let remaining = timeout - Double(DispatchTime.now().uptimeNanoseconds - started) / 1_000_000_000
            guard remaining > 0 else { throw CLIError("Simulator screenshot capture timed out") }
            let temporary = outputURL.deletingLastPathComponent().appendingPathComponent(".loupe-screenshot-\(UUID().uuidString).png")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
            process.arguments = ["simctl", "io", udid, "screenshot", "--type=png", temporary.path]
            try run(process, temporaryURL: temporary, outputURL: outputURL, timeout: remaining)
        }
    }

    static func publish(_ data: Data, to outputURL: URL) throws {
        guard data.suffix(12) == Data([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]),
              let source = CGImageSourceCreateWithData(data as CFData, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil),
              image.width > 0, image.height > 0 else {
            throw CLIError("Incomplete simulator framebuffer PNG")
        }
        try data.write(to: outputURL, options: .atomic)
    }

    static func run(
        _ process: Process, temporaryURL: URL, outputURL: URL, timeout: TimeInterval = 10
    ) throws {
        guard !FileManager.default.fileExists(atPath: temporaryURL.path) else {
            throw CLIError("Screenshot temporary file already exists")
        }
        defer { try? FileManager.default.removeItem(at: temporaryURL) }
        let diagnosticURL = outputURL.appendingPathExtension("stderr.log")
        guard FileManager.default.createFile(atPath: diagnosticURL.path, contents: nil, attributes: [.posixPermissions: 0o600]) else {
            throw CLIError("Could not create screenshot diagnostic file")
        }
        let diagnostics = try FileHandle(forWritingTo: diagnosticURL)
        defer { try? diagnostics.close() }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = diagnostics
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }
        let startedAt = DispatchTime.now().uptimeNanoseconds
        try process.run()
        defer { reap(process, exited: exited) }
        do {
            while Double(DispatchTime.now().uptimeNanoseconds - startedAt) / 1_000_000_000 < timeout {
                if !process.isRunning, process.terminationStatus != 0 {
                    throw CLIError("simctl screenshot exited with status \(process.terminationStatus)")
                }
                if completePNG(at: temporaryURL) {
                    reap(process, exited: exited)
                    guard !process.isRunning else { throw CLIError("Could not reap screenshot process") }
                    guard rename(temporaryURL.path, outputURL.path) == 0 else {
                        throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
                    }
                    return
                }
                if !process.isRunning { throw CLIError("simctl screenshot did not produce a complete PNG") }
                _ = exited.wait(timeout: .now() + 0.02)
            }
            throw CLIError("simctl screenshot timed out after \(timeout)s")
        } catch {
            let text = (try? String(contentsOf: diagnosticURL, encoding: .utf8)) ?? ""
            let tail = text.split(separator: "\n").suffix(8).joined(separator: "\n")
            throw CLIError("\(error)\(tail.isEmpty ? "" : "\n" + tail)")
        }
    }

    private static func completePNG(at url: URL) -> Bool {
        guard let file = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? file.close() }
        guard let count = try? file.seekToEnd(), count >= 12,
              (try? file.seek(toOffset: count - 12)) != nil,
              let tail = try? file.read(upToCount: 12),
              tail == Data([0, 0, 0, 0, 73, 69, 78, 68, 174, 66, 96, 130]),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              CGImageSourceGetStatus(source) == .statusComplete,
              let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { return false }
        return image.width > 0 && image.height > 0
    }

    private static func reap(_ process: Process, exited: DispatchSemaphore) {
        guard process.isRunning else { return }
        process.terminate()
        if exited.wait(timeout: .now() + 0.25) == .timedOut, process.isRunning {
            kill(process.processIdentifier, SIGKILL)
            _ = exited.wait(timeout: .now() + 1)
        }
    }
}
