import Foundation
import Testing
@testable import LoupeCLI

struct SimulatorNativeWorkTests {
    @Test func nativeWaitRunsOutsideSwiftTasksAndAllowsCallbacks() async throws {
        let callback = DispatchSemaphore(value: 0)
        let result = try await SimulatorNativeWork.run {
            let occupiesSwiftTask = withUnsafeCurrentTask { $0 != nil }
            Task { callback.signal() }
            return (occupiesSwiftTask: occupiesSwiftTask,
                    completed: callback.wait(timeout: .now() + 5) == .success)
        }
        #expect(!result.occupiesSwiftTask, "Blocking native work must run outside Swift tasks")
        #expect(result.completed, "Blocking native work must leave Swift's executor free for callbacks")
    }
}
