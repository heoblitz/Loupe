@testable import LoupeCLI
import Testing

@Suite struct QueryOptionsTests {
    @Test func observationsRejectConflictingSelectors() {
        #expect(throws: (any Error).self) {
            try QueryOptions(["--test-id", "button", "--role", "textField"])
        }
        #expect(throws: (any Error).self) {
            try TreeOptions(["--ref", "n1", "--ref", "n2"])
        }
        #expect(throws: (any Error).self) {
            try InspectOptions(["/tmp/example.json", "--ref", "n1", "--text", "other"])
        }
    }
    @Test func parsesWaitForLiveQuery() throws {
        let options = try QueryOptions(["--test-id", "checkout.pay", "--wait", "--timeout", "2"])

        #expect(options.waitForMatch)
        #expect(options.timeout == 2)
        #expect(options.snapshotURL == nil)
    }

    @Test func rejectsWaitForSnapshotQuery() {
        #expect(throws: (any Error).self) {
            _ = try QueryOptions(["/tmp/snapshot.json", "--test-id", "checkout.pay", "--wait"])
        }
    }
}
