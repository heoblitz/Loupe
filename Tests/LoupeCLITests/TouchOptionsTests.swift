@testable import LoupeCLI
@testable import LoupeCLIModel
import LoupeCore
import Testing

struct TouchOptionsTests {
    @Test func preservesExplicitActivationAndUsesTouchForPhysicalGestures() {
        let identity = LoupeRuntimeIdentity(platform: "iOS", deviceIdentifier: "PHONE", processIdentifier: 1)
        for command in ["tap", "swipe", "drag"] {
            #expect(LoupeCLI.resolvedActionBackend(requested: "auto", command: command, runtimeIdentity: identity) == "touch")
        }
        #expect(LoupeCLI.resolvedActionBackend(requested: "runtime", command: "tap", runtimeIdentity: identity) == "runtime")
    }

    @Test func usesExistingDurationAndRejectsInvalidTiming() throws {
        let options = try ActionOptions(command: "tap", arguments: ["--test-id", "gesture", "--duration", "0.7"])
        #expect(options.duration == 0.7)
        for raw in ["nan", "inf", "-1", "11"] {
            #expect(throws: CLIError.self) {
                try ActionOptions(command: "tap", arguments: ["--test-id", "gesture", "--duration", raw])
            }
        }
    }

    @Test func privateTouchControlsAreNotPublicCLIOptions() async {
        #expect(throws: CLIError.self) {
            try ActionOptions(command: "tap", arguments: ["--test-id", "gesture", "--hold-duration", "0.7"])
        }
        await #expect(throws: CLIError.self) {
            try await LoupeCLI.action(command: "tap", arguments: ["--test-id", "gesture", "--backend", "touch"])
        }
    }
}
