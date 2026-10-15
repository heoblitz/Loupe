import Foundation
import Testing
@testable import LoupeCLI

struct SimulatorNativeWorkTests {
    @Test @MainActor func nativeWaitAllowsCallerActorToServiceCallbacks() async throws {
        let callback = DispatchSemaphore(value: 0)
        let completed = try await SimulatorNativeWork.run {
            DispatchQueue.main.async { callback.signal() }
            return callback.wait(timeout: .now() + 5) == .success
        }
        #expect(completed, "Blocking native work must release the caller's actor for callbacks")
    }
}
