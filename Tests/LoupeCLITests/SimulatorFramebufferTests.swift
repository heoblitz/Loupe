import Foundation
import Testing
@testable import LoupeCLI

struct SimulatorFramebufferTests {
    @Test func returnsCompletedFrame() throws {
        let frame = Data([1, 2, 3])
        let captured = try SimulatorFramebuffer.capture(udid: "device", timeout: 1) { id in
            #expect(id == "device")
            return frame
        }
        #expect(captured == frame)
    }

    @Test func blockedNativeCaptureDoesNotBlockDeadline() throws {
        let release = DispatchSemaphore(value: 0)
        let finished = DispatchSemaphore(value: 0)
        defer {
            release.signal()
            #expect(finished.wait(timeout: .now() + 2) == .success)
        }
        #expect(throws: (any Error).self) {
            try SimulatorFramebuffer.capture(udid: "device", timeout: 0.02) { _ in
                release.wait()
                finished.signal()
                return Data([1])
            }
        }
    }
}
