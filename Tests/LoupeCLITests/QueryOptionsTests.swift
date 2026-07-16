@testable import LoupeCLI
import Testing

@Suite struct QueryOptionsTests {
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
