import Foundation
import LoupeHID
import LoupeCLIModel
import os

enum SimulatorFramebuffer {
    // Native framework calls may block. A late capture may release its buffers,
    // but must never write an output after the caller's deadline has expired.
    static func capture(
        udid: String, timeout: TimeInterval,
        read: @escaping @Sendable (String) -> Data? = readNative
    ) throws -> Data? {
        let result = OSAllocatedUnfairLock<Data?>(initialState: nil)
        let completed = DispatchSemaphore(value: 0)
        DispatchQueue.global(qos: .userInitiated).async {
            let data = read(udid)
            result.withLock { $0 = data }
            completed.signal()
        }
        guard completed.wait(timeout: .now() + timeout) == .success else {
            throw CLIError("simulator framebuffer capture timed out after \(timeout)s")
        }
        return result.withLock { $0 }
    }

    private static func readNative(_ udid: String) -> Data? {
        var bytes: UnsafeMutableRawPointer?
        var count = 0
        var error: UnsafeMutablePointer<CChar>?
        let status = LoupeSimulatorCopyPNG(udid, &bytes, &count, &error)
        defer {
            if let bytes { LoupeSimulatorFreeBuffer(bytes) }
            if let error { LoupeHIDFreeCString(error) }
        }
        guard status == 0, let bytes, count > 0 else { return nil }
        return Data(bytes: bytes, count: count)
    }
}
