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

    @Test func parsesHeldTapAndRejectsInvalidTiming() throws {
        let options = try ActionOptions(command: "tap", arguments: ["--test-id", "gesture", "--hold-duration", "0.7"])
        #expect(options.holdDuration == 0.7)
        for raw in ["nan", "inf", "-1", "11"] {
            #expect(throws: CLIError.self) {
                try ActionOptions(command: "tap", arguments: ["--test-id", "gesture", "--hold-duration", raw])
            }
        }
        #expect(throws: CLIError.self) {
            try ActionOptions(command: "swipe", arguments: ["--from", "10,10", "--to", "10,100", "--hold-duration", "0.7"])
        }
    }
}
