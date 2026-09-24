@testable import LoupeCLI
import Testing

@Suite struct OfflineSnapshotRuntimeSelectionTests {
    @Test func optionalSnapshotCommandsRejectLiveRuntimeSelection() {
        let runtimeSelections = [
            ["--host", "http://127.0.0.1:9000"],
            ["--udid", "SIM-UDID"],
            ["--bundle-id", "com.example.App"],
        ]

        for runtimeSelection in runtimeSelections {
            #expect(throws: (any Error).self) {
                try QueryOptions(["/tmp/snapshot.json", "--ref", "node"] + runtimeSelection)
            }
            #expect(throws: (any Error).self) {
                try TreeOptions(["/tmp/snapshot.json", "--ref", "node"] + runtimeSelection)
            }
            #expect(throws: (any Error).self) {
                try ScreenMapOptions(["/tmp/snapshot.json"] + runtimeSelection)
            }
            #expect(throws: (any Error).self) {
                try PaintStackOptions(["/tmp/snapshot.json", "--ref", "node"] + runtimeSelection)
            }
            #expect(throws: (any Error).self) {
                try CompactOptions(["/tmp/snapshot.json"] + runtimeSelection)
            }
            #expect(throws: (any Error).self) {
                try ConstraintListOptions(["/tmp/snapshot.json", "--ref", "node"] + runtimeSelection)
            }
        }
    }

    @Test func inputAliasRequiresStableTestIDBeforeDispatch() throws {
        #expect(throws: (any Error).self) {
            try LoupeCLI.inputFocusSelector(forSavedAliasTestID: nil)
        }
        #expect(try LoupeCLI.inputFocusSelector(forSavedAliasTestID: "checkout.card")
            == .testID("checkout.card"))
        #expect(try LoupeCLI.inputRetryTargetArguments(.ref("explicit-ref")) == ["--ref", "explicit-ref"])
    }
}
